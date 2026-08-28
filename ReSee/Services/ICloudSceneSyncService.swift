import Foundation

enum ICloudSyncState: Equatable {
    case disabled
    case idle
    case syncing
    case unavailable(String)
    case failed(String)

    var title: String {
        switch self {
        case .disabled: "未开启"
        case .idle: "已同步"
        case .syncing: "正在同步"
        case .unavailable: "iCloud 不可用"
        case .failed: "同步失败"
        }
    }

    var detail: String? {
        switch self {
        case let .unavailable(message), let .failed(message): message
        default: nil
        }
    }
}

enum ICloudSceneSyncError: LocalizedError {
    case containerUnavailable

    var errorDescription: String? {
        switch self {
        case .containerUnavailable:
            "请确认设备已登录 iCloud，并为回见开启 iCloud Drive。"
        }
    }
}

actor ICloudSceneSyncService {
    private let fileManager: FileManager
    private let injectedCloudRootURL: URL?

    init(fileManager: FileManager = .default, cloudRootURL: URL? = nil) {
        self.fileManager = fileManager
        injectedCloudRootURL = cloudRootURL
    }

    func synchronize(localRootURL: URL) throws -> [SpatialScene] {
        let cloudRootURL = try resolvedCloudRootURL()
        try fileManager.createDirectory(at: localRootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cloudRootURL, withIntermediateDirectories: true)

        let localScenes = try loadScenes(at: localRootURL.appendingPathComponent("scenes.json"))
        let cloudScenes = try loadScenes(at: cloudRootURL.appendingPathComponent("scenes.json"))
        let localByID = Dictionary(uniqueKeysWithValues: localScenes.map { ($0.id, $0) })
        let cloudByID = Dictionary(uniqueKeysWithValues: cloudScenes.map { ($0.id, $0) })
        let sceneIDs = Set(localByID.keys).union(cloudByID.keys)

        var merged: [SpatialScene] = []
        for sceneID in sceneIDs {
            let localScene = localByID[sceneID]
            let cloudScene = cloudByID[sceneID]
            let shouldUseCloud = localScene == nil
                || (cloudScene?.updatedAt ?? .distantPast) > (localScene?.updatedAt ?? .distantPast)
            guard let selectedScene = shouldUseCloud ? cloudScene : localScene else { continue }

            let sourceRoot = shouldUseCloud ? cloudRootURL : localRootURL
            let destinationRoot = shouldUseCloud ? localRootURL : cloudRootURL
            try copySceneDirectory(
                sceneID: sceneID,
                from: sourceRoot,
                to: destinationRoot
            )
            merged.append(selectedScene)
        }

        merged.sort { $0.updatedAt > $1.updatedAt }
        try writeScenes(merged, at: localRootURL.appendingPathComponent("scenes.json"))
        try writeScenes(merged, at: cloudRootURL.appendingPathComponent("scenes.json"))
        return merged
    }

    func uploadSnapshot(localRootURL: URL, scenes: [SpatialScene]) throws {
        let cloudRootURL = try resolvedCloudRootURL()
        try fileManager.createDirectory(at: cloudRootURL, withIntermediateDirectories: true)
        for scene in scenes {
            try copySceneDirectory(sceneID: scene.id, from: localRootURL, to: cloudRootURL)
        }
        try writeScenes(scenes, at: cloudRootURL.appendingPathComponent("scenes.json"))
    }

    func remove(sceneIDs: [UUID], localRootURL: URL, scenes: [SpatialScene]) throws {
        let cloudRootURL = try resolvedCloudRootURL()
        for sceneID in sceneIDs {
            let sceneURL = cloudRootURL.appendingPathComponent(sceneID.uuidString, isDirectory: true)
            if fileManager.fileExists(atPath: sceneURL.path) {
                try fileManager.removeItem(at: sceneURL)
            }
        }
        try uploadSnapshot(localRootURL: localRootURL, scenes: scenes)
    }

    private func resolvedCloudRootURL() throws -> URL {
        let containerURL = injectedCloudRootURL
            ?? fileManager.url(forUbiquityContainerIdentifier: nil)
        guard let containerURL else { throw ICloudSceneSyncError.containerUnavailable }
        return containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("回见", isDirectory: true)
            .appendingPathComponent("Scenes", isDirectory: true)
    }

    private func copySceneDirectory(sceneID: UUID, from sourceRoot: URL, to destinationRoot: URL) throws {
        let sourceURL = sourceRoot.appendingPathComponent(sceneID.uuidString, isDirectory: true)
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }
        let destinationURL = destinationRoot.appendingPathComponent(sceneID.uuidString, isDirectory: true)
        let stagingURL = destinationRoot.appendingPathComponent(
            ".sync-\(sceneID.uuidString)-\(UUID().uuidString)",
            isDirectory: true
        )
        if fileManager.fileExists(atPath: stagingURL.path) {
            try fileManager.removeItem(at: stagingURL)
        }
        try fileManager.copyItem(at: sourceURL, to: stagingURL)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: stagingURL, to: destinationURL)
    }

    private func loadScenes(at url: URL) throws -> [SpatialScene] {
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder.sceneSyncDecoder.decode(
            [SpatialScene].self,
            from: Data(contentsOf: url)
        )
    }

    private func writeScenes(_ scenes: [SpatialScene], at url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.sceneSyncEncoder.encode(scenes).write(to: url, options: .atomic)
    }
}

private extension JSONEncoder {
    static var sceneSyncEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var sceneSyncDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
