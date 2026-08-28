import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class ExternalAssetRepository: ObservableObject {
    @Published private(set) var assets: [ExternalAsset] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isTransferring = false
    @Published private(set) var transferProgressDescription: String?
    @Published private(set) var iCloudSyncState: ICloudSyncState = .disabled
    @Published private(set) var lastICloudSyncAt: Date?

    private let fileManager: FileManager
    private let rootURL: URL
    private let indexURL: URL
    private let cloudSyncService: ICloudExternalAssetSyncService
    private var isICloudMetadataEnabled = false
    private var includesICloudFiles = false

    init(
        fileManager: FileManager = .default,
        rootURL: URL? = nil,
        cloudSyncService: ICloudExternalAssetSyncService? = nil
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL ?? ExternalAssetStore.rootURL(fileManager: fileManager)
        indexURL = self.rootURL.appendingPathComponent("assets.json")
        self.cloudSyncService = cloudSyncService
            ?? ICloudExternalAssetSyncService(fileManager: fileManager)
        load()
    }

    func importFiles(urls: [URL], copyIntoLibrary: Bool, name: String? = nil) async {
        await performTransfer(description: copyIntoLibrary ? "正在复制文件" : "正在建立文件引用") {
            let kind = try ExternalAssetFormat.kind(for: urls)
            let id = UUID()
            var files: [ExternalAssetFile] = []
            do {
                for (index, url) in urls.enumerated() {
                    files.append(try await makeFile(
                        from: url,
                        assetID: id,
                        index: index,
                        copyIntoLibrary: copyIntoLibrary
                    ))
                }
            } catch {
                if copyIntoLibrary { try? removeManagedDirectory(assetID: id) }
                throw error
            }
            let defaultName = urls.count == 1
                ? urls[0].deletingPathExtension().lastPathComponent
                : "多点全景 \(assets.count + 1)"
            let asset = ExternalAsset(
                id: id,
                name: normalizedName(name, fallback: defaultName),
                kind: kind,
                storage: copyIntoLibrary ? .copied : .linked,
                createdAt: .now,
                updatedAt: .now,
                sourceURL: nil,
                files: files
            )
            try insert(asset)
        }
    }

    func download(from address: String, name: String? = nil) async {
        await performTransfer(description: "正在下载外部资源") {
            guard let remoteURL = URL(string: address),
                  ["http", "https"].contains(remoteURL.scheme?.lowercased() ?? "") else {
                throw ExternalAssetError.invalidDownloadURL
            }

            let (temporaryURL, response) = try await URLSession.shared.download(from: remoteURL)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ExternalAssetError.downloadFailed("服务器返回 HTTP \(http.statusCode)")
            }
            let suggestedName = response.suggestedFilename
                ?? remoteURL.lastPathComponent.nonEmpty
                ?? "download"
            let stagedURL = fileManager.temporaryDirectory
                .appendingPathComponent("resee-\(UUID().uuidString)-\(suggestedName)")
            try fileManager.moveItem(at: temporaryURL, to: stagedURL)
            defer { try? fileManager.removeItem(at: stagedURL) }

            let kind = try ExternalAssetFormat.kind(for: [stagedURL])
            let id = UUID()
            let file = try await makeFile(
                from: stagedURL,
                assetID: id,
                index: 0,
                copyIntoLibrary: true,
                preferredName: suggestedName
            )
            let asset = ExternalAsset(
                id: id,
                name: normalizedName(
                    name,
                    fallback: URL(fileURLWithPath: suggestedName).deletingPathExtension().lastPathComponent
                ),
                kind: kind,
                storage: .downloaded,
                createdAt: .now,
                updatedAt: .now,
                sourceURL: remoteURL.absoluteString,
                files: [file]
            )
            try insert(asset)
        }
    }

    func delete(at offsets: IndexSet) {
        let valid = IndexSet(offsets.filter { assets.indices.contains($0) })
        guard !valid.isEmpty else { return }
        let removed = valid.map { assets[$0] }
        var updated = assets
        updated.remove(atOffsets: valid)
        do {
            try save(updated)
            for asset in removed where asset.storage.isManaged {
                let directory = rootURL.appendingPathComponent(asset.id.uuidString, isDirectory: true)
                if fileManager.fileExists(atPath: directory.path) {
                    try fileManager.removeItem(at: directory)
                }
            }
            scheduleCloudUpload(removing: removed.map(\.id))
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearError() { lastError = nil }

    func report(_ error: Error) {
        lastError = error.localizedDescription
    }

    func configureICloudSync(enabled: Bool, includeMetadata: Bool, includeFiles: Bool) async {
        isICloudMetadataEnabled = enabled && includeMetadata
        includesICloudFiles = includeFiles
        guard isICloudMetadataEnabled else {
            iCloudSyncState = .disabled
            return
        }
        await synchronizeWithICloud()
    }

    func synchronizeWithICloud() async {
        guard isICloudMetadataEnabled else { return }
        iCloudSyncState = .syncing
        do {
            assets = try await cloudSyncService.synchronize(
                localRootURL: rootURL,
                includeFiles: includesICloudFiles
            )
            lastICloudSyncAt = .now
            iCloudSyncState = .idle
        } catch ICloudSceneSyncError.containerUnavailable {
            iCloudSyncState = .unavailable(
                ICloudSceneSyncError.containerUnavailable.localizedDescription
            )
        } catch {
            iCloudSyncState = .failed(error.localizedDescription)
        }
    }

    func scopedAccess(to asset: ExternalAsset) throws -> ScopedExternalAsset {
        let resources = try asset.files.map { file -> ScopedExternalAsset.Resource in
            if let relativePath = file.relativePath {
                return .init(
                    file: file,
                    url: rootURL.appendingPathComponent(asset.id.uuidString).appendingPathComponent(relativePath),
                    hasSecurityScope: false
                )
            }
            guard let bookmarkData = file.bookmarkData else {
                throw ExternalAssetError.inaccessibleFile(file.displayName)
            }
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            let accessed = url.startAccessingSecurityScopedResource()
            guard accessed else { throw ExternalAssetError.inaccessibleFile(file.displayName) }
            return .init(file: file, url: url, hasSecurityScope: true)
        }
        return ScopedExternalAsset(asset: asset, resources: resources)
    }

    private func performTransfer(
        description: String,
        operation: () async throws -> Void
    ) async {
        isTransferring = true
        transferProgressDescription = description
        defer {
            isTransferring = false
            transferProgressDescription = nil
        }
        do {
            try await operation()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func makeFile(
        from sourceURL: URL,
        assetID: UUID,
        index: Int,
        copyIntoLibrary: Bool,
        preferredName: String? = nil
    ) async throws -> ExternalAssetFile {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }

        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        let displayName = preferredName ?? sourceURL.lastPathComponent
        let dimensions = imageDimensions(at: sourceURL)
        var relativePath: String?
        var bookmarkData: Data?

        if copyIntoLibrary {
            let directory = rootURL.appendingPathComponent(assetID.uuidString, isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let safeName = uniqueFileName(index: index, originalName: displayName)
            relativePath = "files/\(safeName)"
            let destination = directory.appendingPathComponent(relativePath!)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let fileManager = fileManager
            try await Task.detached(priority: .userInitiated) {
                try fileManager.copyItem(at: sourceURL, to: destination)
            }.value
        } else {
            bookmarkData = try sourceURL.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }

        return ExternalAssetFile(
            id: UUID(),
            displayName: displayName,
            relativePath: relativePath,
            bookmarkData: bookmarkData,
            byteCount: Int64(values.fileSize ?? 0),
            contentTypeIdentifier: values.contentType?.identifier,
            pixelWidth: dimensions?.width,
            pixelHeight: dimensions?.height
        )
    }

    private func imageDimensions(at url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }

    private func uniqueFileName(index: Int, originalName: String) -> String {
        let source = URL(fileURLWithPath: originalName)
        let base = source.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "/", with: "-")
        let ext = source.pathExtension.lowercased()
        return String(format: "%02d-%@.%@", index + 1, base, ext)
    }

    private func normalizedName(_ name: String?, fallback: String) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func removeManagedDirectory(assetID: UUID) throws {
        let directory = rootURL.appendingPathComponent(assetID.uuidString, isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    private func insert(_ asset: ExternalAsset) throws {
        var updated = assets.filter { $0.id != asset.id }
        updated.insert(asset, at: 0)
        try save(updated)
        scheduleCloudUpload()
    }

    private func scheduleCloudUpload(removing ids: [UUID] = []) {
        guard isICloudMetadataEnabled else { return }
        let currentAssets = assets
        let includeFiles = includesICloudFiles
        Task {
            do {
                iCloudSyncState = .syncing
                if ids.isEmpty {
                    try await cloudSyncService.upload(
                        localRootURL: rootURL,
                        assets: currentAssets,
                        includeFiles: includeFiles
                    )
                } else {
                    try await cloudSyncService.remove(
                        ids: ids,
                        localRootURL: rootURL,
                        assets: currentAssets,
                        includeFiles: includeFiles
                    )
                }
                lastICloudSyncAt = .now
                iCloudSyncState = .idle
            } catch {
                iCloudSyncState = .failed(error.localizedDescription)
            }
        }
    }

    private func load() {
        guard fileManager.fileExists(atPath: indexURL.path) else { return }
        do {
            assets = try Self.decoder.decode([ExternalAsset].self, from: Data(contentsOf: indexURL))
        } catch {
            lastError = "外部资源索引读取失败：\(error.localizedDescription)"
        }
    }

    private func save(_ updated: [ExternalAsset]) throws {
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
            try Self.encoder.encode(updated).write(to: indexURL, options: .atomic)
            assets = updated
        } catch {
            throw ExternalAssetError.saveFailed(error.localizedDescription)
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

final class ScopedExternalAsset {
    struct Resource {
        let file: ExternalAssetFile
        let url: URL
        let hasSecurityScope: Bool
    }

    let asset: ExternalAsset
    let resources: [Resource]

    init(asset: ExternalAsset, resources: [Resource]) {
        self.asset = asset
        self.resources = resources
    }

    deinit {
        resources.filter(\.hasSecurityScope).forEach { $0.url.stopAccessingSecurityScopedResource() }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
