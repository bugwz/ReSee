import Foundation

struct SpatialScene: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var capture: CaptureSummary
    var modelVersion: String
    var annotations: [SpatialAnnotation]

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        capture: CaptureSummary,
        modelVersion: String = "capture-v1",
        annotations: [SpatialAnnotation] = []
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.capture = capture
        self.modelVersion = modelVersion
        self.annotations = annotations
    }
}

struct CaptureSummary: Codable, Hashable {
    var duration: TimeInterval
    var meshAnchorCount: Int
    var supportsLiDAR: Bool
    var trackingQuality: TrackingQuality

    static let empty = CaptureSummary(
        duration: 0,
        meshAnchorCount: 0,
        supportsLiDAR: false,
        trackingQuality: .unavailable
    )
}

enum TrackingQuality: String, Codable, Hashable {
    case unavailable
    case limited
    case normal

    var title: String {
        switch self {
        case .unavailable: "等待定位"
        case .limited: "定位受限"
        case .normal: "定位稳定"
        }
    }
}

