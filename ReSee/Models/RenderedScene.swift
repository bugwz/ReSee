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
    var forwardHeadingDegrees: Float

    init(
        id: UUID,
        index: Int,
        name: String,
        position: Vector3,
        panoramaPath: String,
        sourceFrameCount: Int,
        forwardHeadingDegrees: Float = 0
    ) {
        self.id = id
        self.index = index
        self.name = name
        self.position = position
        self.panoramaPath = panoramaPath
        self.sourceFrameCount = sourceFrameCount
        self.forwardHeadingDegrees = forwardHeadingDegrees
    }

    private enum CodingKeys: String, CodingKey {
        case id, index, name, position, panoramaPath, sourceFrameCount
        case forwardHeadingDegrees
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        index = try container.decode(Int.self, forKey: .index)
        name = try container.decode(String.self, forKey: .name)
        position = try container.decode(Vector3.self, forKey: .position)
        panoramaPath = try container.decode(String.self, forKey: .panoramaPath)
        sourceFrameCount = try container.decode(Int.self, forKey: .sourceFrameCount)
        forwardHeadingDegrees = try container.decodeIfPresent(
            Float.self,
            forKey: .forwardHeadingDegrees
        ) ?? 0
    }
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
