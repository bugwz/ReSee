import Foundation

struct SpatialScene: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var capture: CaptureSummary
    var recordingType: RecordingType
    var modelVersion: String
    var annotations: [SpatialAnnotation]
    var renderedScene: RenderedScene?

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        capture: CaptureSummary,
        recordingType: RecordingType = .stationary,
        modelVersion: String = "capture-v1",
        annotations: [SpatialAnnotation] = [],
        renderedScene: RenderedScene? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.capture = capture
        self.recordingType = recordingType
        self.modelVersion = modelVersion
        self.annotations = annotations
        self.renderedScene = renderedScene
    }

}

struct CaptureSummary: Codable, Hashable {
    var duration: TimeInterval
    var meshAnchorCount: Int
    var supportsLiDAR: Bool
    var trackingQuality: TrackingQuality
    var capturedFrameCount: Int
    var viewpointCount: Int
    var coverage: Double

    init(
        duration: TimeInterval,
        meshAnchorCount: Int,
        supportsLiDAR: Bool,
        trackingQuality: TrackingQuality,
        capturedFrameCount: Int = 0,
        viewpointCount: Int = 0,
        coverage: Double = 0
    ) {
        self.duration = duration
        self.meshAnchorCount = meshAnchorCount
        self.supportsLiDAR = supportsLiDAR
        self.trackingQuality = trackingQuality
        self.capturedFrameCount = capturedFrameCount
        self.viewpointCount = viewpointCount
        self.coverage = coverage
    }

    static let empty = CaptureSummary(
        duration: 0,
        meshAnchorCount: 0,
        supportsLiDAR: false,
        trackingQuality: .unavailable,
        capturedFrameCount: 0,
        viewpointCount: 0,
        coverage: 0
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
