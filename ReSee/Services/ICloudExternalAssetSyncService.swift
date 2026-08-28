import Foundation

actor ICloudExternalAssetSyncService {
    private let fileManager: FileManager
    private let injectedCloudRootURL: URL?

    init(fileManager: FileManager = .default, cloudRootURL: URL? = nil) {
        self.fileManager = fileManager
        injectedCloudRootURL = cloudRootURL
    }

    func synchronize(localRootURL: URL, includeFiles: Bool) throws -> [ExternalAsset] {
        let cloudRootURL = try resolvedCloudRootURL()
        try fileManager.createDirectory(at: localRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cloudRootURL, withIntermediateDirectories: true)
        let local = try load(at: localRootURL.appendingPathComponent("assets.json"))
        let cloud = try load(at: cloudRootURL.appendingPathComponent("assets.json"))
        let localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let cloudByID = Dictionary(uniqueKeysWithValues: cloud.map { ($0.id, $0) })
        var merged: [ExternalAsset] = []

        for id in Set(localByID.keys).union(cloudByID.keys) {
            let localAsset = localByID[id]
            let cloudAsset = cloudByID[id]
            let useCloud = localAsset == nil
                || (cloudAsset?.updatedAt ?? .distantPast) > (localAsset?.updatedAt ?? .distantPast)
            guard let selected = useCloud ? cloudAsset : localAsset else { continue }
            if includeFiles, selected.storage.isManaged {
                try copyDirectory(
                    id: id,
                    from: useCloud ? cloudRootURL : localRootURL,
                    to: useCloud ? localRootURL : cloudRootURL
                )
            }
            merged.append(selected)
        }

        merged.sort { $0.updatedAt > $1.updatedAt }
        try write(merged, at: localRootURL.appendingPathComponent("assets.json"))
        try write(merged, at: cloudRootURL.appendingPathComponent("assets.json"))
        return merged
    }

    func upload(localRootURL: URL, assets: [ExternalAsset], includeFiles: Bool) throws {
        let cloudRootURL = try resolvedCloudRootURL()
        try fileManager.createDirectory(at: cloudRootURL, withIntermediateDirectories: true)
        if includeFiles {
            for asset in assets where asset.storage.isManaged {
                try copyDirectory(id: asset.id, from: localRootURL, to: cloudRootURL)
            }
        }
        try write(assets, at: cloudRootURL.appendingPathComponent("assets.json"))
    }

    func remove(ids: [UUID], localRootURL: URL, assets: [ExternalAsset], includeFiles: Bool) throws {
        let cloudRootURL = try resolvedCloudRootURL()
        for id in ids {
            let directory = cloudRootURL.appendingPathComponent(id.uuidString, isDirectory: true)
            if fileManager.fileExists(atPath: directory.path) { try fileManager.removeItem(at: directory) }
        }
        try upload(localRootURL: localRootURL, assets: assets, includeFiles: includeFiles)
    }

    private func resolvedCloudRootURL() throws -> URL {
        let container = injectedCloudRootURL ?? fileManager.url(forUbiquityContainerIdentifier: nil)
        guard let container else { throw ICloudSceneSyncError.containerUnavailable }
        return container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("回见", isDirectory: true)
            .appendingPathComponent("ExternalAssets", isDirectory: true)
    }

    private func copyDirectory(id: UUID, from sourceRoot: URL, to destinationRoot: URL) throws {
        let source = sourceRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        guard fileManager.fileExists(atPath: source.path) else { return }
        let destination = destinationRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let staging = destinationRoot.appendingPathComponent(".sync-\(id)-\(UUID())", isDirectory: true)
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        try fileManager.copyItem(at: source, to: staging)
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.moveItem(at: staging, to: destination)
    }

    private func load(at url: URL) throws -> [ExternalAsset] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try Self.decoder.decode([ExternalAsset].self, from: Data(contentsOf: url))
    }

    private func write(_ assets: [ExternalAsset], at url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(assets).write(to: url, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .iso8601
        value.outputFormatting = [.prettyPrinted, .sortedKeys]
        return value
    }

    private static var decoder: JSONDecoder {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }
}
