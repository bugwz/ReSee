import Foundation

enum SceneRepositoryError: LocalizedError {
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case let .saveFailed(reason):
            "场景索引保存失败：\(reason)"
        }
    }
}

@MainActor
final class SceneRepository: ObservableObject {
    @Published private(set) var scenes: [SpatialScene] = []
    @Published private(set) var lastError: String?
    @Published private(set) var iCloudSyncState: ICloudSyncState = .disabled
    @Published private(set) var lastICloudSyncAt: Date?

    private let fileManager: FileManager
    private let storeURL: URL
    private let cloudSyncService: ICloudSceneSyncService
    private var isICloudSyncEnabled = false
    private var includesICloudRenderedFiles = true

    init(
        fileManager: FileManager = .default,
        storeURL: URL? = nil,
        cloudSyncService: ICloudSceneSyncService? = nil
    ) {
        self.fileManager = fileManager
        self.cloudSyncService = cloudSyncService ?? ICloudSceneSyncService(fileManager: fileManager)

        if let storeURL {
            self.storeURL = storeURL
        } else {
            let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.storeURL = baseURL
                .appendingPathComponent("Scenes", isDirectory: true)
                .appendingPathComponent("scenes.json")
        }

        load()
    }

    func add(name: String, summary: CaptureSummary) throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = "未命名空间 \(scenes.count + 1)"
        let scene = SpatialScene(
            name: trimmedName.isEmpty ? fallbackName : trimmedName,
            capture: summary
        )
        try add(scene)
    }

    func add(_ scene: SpatialScene) throws {
        var updatedScenes = scenes.filter { $0.id != scene.id }
        updatedScenes.insert(scene, at: 0)
        try save(updatedScenes)
        scheduleCloudUpload()
    }

    func delete(at offsets: IndexSet) {
        let validOffsets = IndexSet(offsets.filter { scenes.indices.contains($0) })
        guard !validOffsets.isEmpty else { return }

        let deletedScenes = validOffsets.map { scenes[$0] }
        var updatedScenes = scenes
        updatedScenes.remove(atOffsets: validOffsets)

        do {
            try save(updatedScenes)
        } catch {
            return
        }

        for scene in deletedScenes {
            let sceneURL = storeURL.deletingLastPathComponent()
                .appendingPathComponent(scene.id.uuidString, isDirectory: true)
            guard fileManager.fileExists(atPath: sceneURL.path) else { continue }
            do {
                try fileManager.removeItem(at: sceneURL)
            } catch {
                lastError = "场景已从列表删除，但本地文件清理失败：\(error.localizedDescription)"
            }
        }

        guard isICloudSyncEnabled else { return }
        let sceneIDs = deletedScenes.map(\.id)
        let currentScenes = scenes
        let rootURL = storeURL.deletingLastPathComponent()
        Task {
            do {
                iCloudSyncState = .syncing
                try await cloudSyncService.remove(
                    sceneIDs: sceneIDs,
                    localRootURL: rootURL,
                    scenes: currentScenes,
                    includeRenderedFiles: includesICloudRenderedFiles
                )
                markCloudSyncCompleted()
            } catch {
                markCloudSyncFailed(error)
            }
        }
    }

    func configureICloudSync(enabled: Bool, includeRenderedFiles: Bool = true) async {
        isICloudSyncEnabled = enabled
        includesICloudRenderedFiles = includeRenderedFiles
        guard enabled else {
            iCloudSyncState = .disabled
            return
        }
        await synchronizeWithICloud()
    }

    func synchronizeWithICloud() async {
        guard isICloudSyncEnabled else {
            iCloudSyncState = .disabled
            return
        }
        iCloudSyncState = .syncing
        do {
            let mergedScenes = try await cloudSyncService.synchronize(
                localRootURL: storeURL.deletingLastPathComponent(),
                includeRenderedFiles: includesICloudRenderedFiles
            )
            scenes = mergedScenes
            markCloudSyncCompleted()
        } catch ICloudSceneSyncError.containerUnavailable {
            iCloudSyncState = .unavailable(
                ICloudSceneSyncError.containerUnavailable.localizedDescription
            )
        } catch {
            markCloudSyncFailed(error)
        }
    }

    func clearError() {
        lastError = nil
    }

    private func load() {
        guard fileManager.fileExists(atPath: storeURL.path) else { return }
        do {
            scenes = try JSONDecoder.sceneDecoder.decode(
                [SpatialScene].self,
                from: Data(contentsOf: storeURL)
            )
        } catch {
            lastError = "场景索引读取失败：\(error.localizedDescription)"
        }
    }

    private func save(_ updatedScenes: [SpatialScene]) throws {
        do {
            try fileManager.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.sceneEncoder.encode(updatedScenes)
            try data.write(to: storeURL, options: .atomic)
            scenes = updatedScenes
            lastError = nil
        } catch {
            let repositoryError = SceneRepositoryError.saveFailed(error.localizedDescription)
            lastError = repositoryError.localizedDescription
            throw repositoryError
        }
    }

    private func scheduleCloudUpload() {
        guard isICloudSyncEnabled else { return }
        let currentScenes = scenes
        let rootURL = storeURL.deletingLastPathComponent()
        Task {
            do {
                iCloudSyncState = .syncing
                try await cloudSyncService.uploadSnapshot(
                    localRootURL: rootURL,
                    scenes: currentScenes,
                    includeRenderedFiles: includesICloudRenderedFiles
                )
                markCloudSyncCompleted()
            } catch {
                markCloudSyncFailed(error)
            }
        }
    }

    private func markCloudSyncCompleted() {
        lastICloudSyncAt = .now
        iCloudSyncState = .idle
    }

    private func markCloudSyncFailed(_ error: Error) {
        iCloudSyncState = .failed(error.localizedDescription)
    }
}

private extension JSONEncoder {
    static var sceneEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var sceneDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
