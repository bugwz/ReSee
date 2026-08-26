import XCTest
@testable import ReSee

final class SpatialSceneTests: XCTestCase {
    func testSceneRoundTripsThroughJSON() throws {
        let annotation = SpatialAnnotation(
            modelVersion: "mesh-v2",
            position: Vector3(x: 1, y: 2, z: 3),
            normal: Vector3(x: 0, y: 1, z: 0),
            meshTriangleID: 42,
            barycentricCoordinate: Vector3(x: 0.2, y: 0.3, z: 0.5),
            title: "配电箱"
        )
        let original = SpatialScene(
            name: "设备间",
            capture: CaptureSummary(
                duration: 65,
                meshAnchorCount: 18,
                supportsLiDAR: true,
                trackingQuality: .normal
            ),
            modelVersion: "mesh-v2",
            annotations: [annotation]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SpatialScene.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.annotations.first?.meshTriangleID, 42)
    }

    func testCaptureCoverageIsBounded() {
        let metrics = CaptureMetrics(
            trackingQuality: .normal,
            meshAnchorCount: 100,
            supportsLiDAR: true
        )

        XCTAssertEqual(metrics.coverage, 1)
    }
}

