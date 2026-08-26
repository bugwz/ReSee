import Foundation

@MainActor
final class SceneRepository: ObservableObject {
    @Published private(set) var scenes: [SpatialScene] = []
    @Published private(set) var lastError: String?

    private let fileManager: FileManager
    private let storeURL: URL

    init(fileManager: FileManager = .default, storeURL: URL? = nil) {
        self.fileManager = fileManager

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

    func add(name: String, summary: CaptureSummary) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = "未命名空间 \(scenes.count + 1)"
        let scene = SpatialScene(
            name: trimmedName.isEmpty ? fallbackName : trimmedName,
            capture: summary
        )
        scenes.insert(scene, at: 0)
        persist()
    }

    func delete(at offsets: IndexSet) {
        scenes.remove(atOffsets: offsets)
        persist()
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

    private func persist() {
        do {
            try fileManager.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder.sceneEncoder.encode(scenes)
            try data.write(to: storeURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = "场景索引保存失败：\(error.localizedDescription)"
        }
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

