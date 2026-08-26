import Foundation

struct SpatialAnnotation: Identifiable, Codable, Hashable {
    let id: UUID
    var modelVersion: String
    var position: Vector3
    var normal: Vector3
    var meshTriangleID: Int?
    var barycentricCoordinate: Vector3?
    var title: String
    var note: String
    var mediaReferences: [String]
    var createdAt: Date

    init(
        id: UUID = UUID(),
        modelVersion: String,
        position: Vector3,
        normal: Vector3,
        meshTriangleID: Int? = nil,
        barycentricCoordinate: Vector3? = nil,
        title: String,
        note: String = "",
        mediaReferences: [String] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.modelVersion = modelVersion
        self.position = position
        self.normal = normal
        self.meshTriangleID = meshTriangleID
        self.barycentricCoordinate = barycentricCoordinate
        self.title = title
        self.note = note
        self.mediaReferences = mediaReferences
        self.createdAt = createdAt
    }
}

struct Vector3: Codable, Hashable {
    var x: Float
    var y: Float
    var z: Float

    static let zero = Vector3(x: 0, y: 0, z: 0)
}

