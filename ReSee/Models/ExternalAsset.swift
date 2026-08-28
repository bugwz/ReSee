import Foundation
import UniformTypeIdentifiers

enum ExternalAssetKind: String, Codable, CaseIterable, Identifiable {
    case stationaryPanorama
    case multiPointPanorama
    case gaussianSplat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stationaryPanorama: "定点全景"
        case .multiPointPanorama: "多点全景"
        case .gaussianSplat: "Gaussian Splatting"
        }
    }

    var systemImage: String {
        switch self {
        case .stationaryPanorama: "view.360"
        case .multiPointPanorama: "point.3.connected.trianglepath.dotted"
        case .gaussianSplat: "cube.transparent"
        }
    }
}

enum ExternalAssetStorage: String, Codable {
    case downloaded
    case copied
    case linked

    var title: String {
        switch self {
        case .downloaded: "网络下载"
        case .copied: "已复制到回见"
        case .linked: "引用原文件"
        }
    }

    var isManaged: Bool { self != .linked }
}

struct ExternalAssetFile: Identifiable, Codable, Hashable {
    var id: UUID
    var displayName: String
    var relativePath: String?
    var bookmarkData: Data?
    var byteCount: Int64
    var contentTypeIdentifier: String?
    var pixelWidth: Int?
    var pixelHeight: Int?

    var fileExtension: String {
        URL(fileURLWithPath: displayName).pathExtension.lowercased()
    }

    var dimensionsText: String? {
        guard let pixelWidth, let pixelHeight else { return nil }
        return "\(pixelWidth) × \(pixelHeight)"
    }
}

struct ExternalAsset: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var kind: ExternalAssetKind
    var storage: ExternalAssetStorage
    var createdAt: Date
    var updatedAt: Date
    var sourceURL: String?
    var files: [ExternalAssetFile]

    var totalByteCount: Int64 { files.reduce(0) { $0 + $1.byteCount } }
    var formatSummary: String {
        let formats = Set(files.map { $0.fileExtension.uppercased() })
        return formats.sorted().joined(separator: "、")
    }
}

enum ExternalAssetFormat {
    static let panoramaExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif"]
    static let gaussianExtensions: Set<String> = ["ply", "splat", "spz"]

    static var importContentTypes: [UTType] {
        let extensions = panoramaExtensions.union(gaussianExtensions).sorted()
        return extensions.compactMap { UTType(filenameExtension: $0) }
    }

    static func kind(for urls: [URL]) throws -> ExternalAssetKind {
        guard !urls.isEmpty else { throw ExternalAssetError.noFiles }
        let extensions = urls.map { $0.pathExtension.lowercased() }
        if extensions.allSatisfy(panoramaExtensions.contains) {
            return urls.count == 1 ? .stationaryPanorama : .multiPointPanorama
        }
        if urls.count == 1, gaussianExtensions.contains(extensions[0]) {
            return .gaussianSplat
        }
        throw ExternalAssetError.mixedOrUnsupportedFormats
    }
}

enum ExternalAssetError: LocalizedError {
    case noFiles
    case mixedOrUnsupportedFormats
    case invalidDownloadURL
    case downloadFailed(String)
    case inaccessibleFile(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .noFiles: "没有选择文件。"
        case .mixedOrUnsupportedFormats: "请选择一张或多张全景图片，或单个 PLY、SPLAT、SPZ 高斯文件。"
        case .invalidDownloadURL: "请输入有效的 HTTP 或 HTTPS 文件地址。"
        case let .downloadFailed(reason): "下载失败：\(reason)"
        case let .inaccessibleFile(name): "无法持续访问“\(name)”，请改为复制到回见。"
        case let .saveFailed(reason): "外部资源保存失败：\(reason)"
        }
    }
}

enum ExternalAssetStore {
    static func rootURL(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ExternalAssets", isDirectory: true)
    }

    static func managedFileURL(
        assetID: UUID,
        relativePath: String,
        fileManager: FileManager = .default
    ) -> URL {
        rootURL(fileManager: fileManager)
            .appendingPathComponent(assetID.uuidString, isDirectory: true)
            .appendingPathComponent(relativePath)
    }
}
