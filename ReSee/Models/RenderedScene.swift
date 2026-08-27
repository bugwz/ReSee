import Foundation

enum SceneGenerationState: String, Codable, Hashable {
    case ready
    case failed
}

struct RenderedScene: Codable, Hashable {
    var generationState: SceneGenerationState
    var generatedAt: Date
    var viewpoints: [RenderedViewpoint]
    var thumbnailPath: String?

    var frameCount: Int {
        viewpoints.reduce(0) { $0 + $1.sourceFrameCount }
    }
}

struct RenderedViewpoint: Identifiable, Codable, Hashable {
    var id: UUID
    var index: Int
    var name: String
    var position: Vector3
    var panoramaPath: String
    var sourceFrameCount: Int
}

struct CameraCalibration: Hashable {
    var cameraTransform: [Float]
    var intrinsics: [Float]
    var imageWidth: Int
    var imageHeight: Int
}

struct CapturedFramePayload: Identifiable, Hashable {
    var id: UUID = UUID()
    var viewpointIndex: Int
    var directionID: Int
    var yawDegrees: Float
    var pitchDegrees: Float
    var position: Vector3
    var calibration: CameraCalibration
    var imageData: Data
}
