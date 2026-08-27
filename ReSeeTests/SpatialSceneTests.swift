import ImageIO
import simd
import UIKit
import XCTest
@testable import ReSee

final class SpatialSceneTests: XCTestCase {
    func testSceneRoundTripsThroughJSON() throws {
        let path = "rendered/viewpoint-00/panorama.jpg"
        let rendered = RenderedScene(
            generationState: .ready,
            generatedAt: .now,
            viewpoints: [RenderedViewpoint(
                id: UUID(), index: 0, name: "点位 1", position: .zero,
                panoramaPath: path, sourceFrameCount: CaptureProgressState.targetCount
            )],
            thumbnailPath: path
        )
        let original = SpatialScene(
            name: "设备间",
            capture: CaptureSummary(
                duration: 65, meshAnchorCount: 18, supportsLiDAR: true,
                trackingQuality: .normal, capturedFrameCount: 52,
                viewpointCount: 1, coverage: 1
            ),
            recordingType: .stationary,
            modelVersion: "equirectangular-v1",
            renderedScene: rendered
        )

        let decoded = try JSONDecoder().decode(
            SpatialScene.self,
            from: JSONEncoder().encode(original)
        )

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.renderedScene?.frameCount, 52)
        XCTAssertEqual(decoded.renderedScene?.viewpoints.first?.panoramaPath, path)
    }

    func testOldSceneWithoutNewFieldsIsRejected() throws {
        let original = SpatialScene(
            name: "旧场景",
            capture: CaptureSummary(
                duration: 10,
                meshAnchorCount: 2,
                supportsLiDAR: false,
                trackingQuality: .limited
            )
        )
        let encoded = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "recordingType")
        let oldData = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try JSONDecoder().decode(SpatialScene.self, from: oldData))
    }

    func testRenderedViewpointDefaultsMissingForwardHeading() throws {
        let viewpoint = RenderedViewpoint(
            id: UUID(),
            index: 0,
            name: "旧点位",
            position: .zero,
            panoramaPath: "rendered/viewpoint-00/panorama.heic",
            sourceFrameCount: 52,
            forwardHeadingDegrees: 37
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(viewpoint))
                as? [String: Any]
        )
        object.removeValue(forKey: "forwardHeadingDegrees")
        let oldData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(RenderedViewpoint.self, from: oldData)
        XCTAssertEqual(decoded.forwardHeadingDegrees, 0)
    }

    func testSphericalCaptureGridContainsFiveBandsAnd52Targets() {
        XCTAssertEqual(CaptureDirection.all.count, 52)
        XCTAssertEqual(CaptureDirection.bands.map(\.count), [8, 12, 12, 12, 8])
        XCTAssertEqual(
            CaptureDirection.bands.map { Int($0[0].pitchDegrees.rounded()) },
            [-75, -38, 0, 38, 75]
        )
        XCTAssertEqual(Set(CaptureDirection.all.map(\.id)).count, 52)
        XCTAssertEqual(CaptureDirection.captureSequence.count, 52)
        XCTAssertEqual(Set(CaptureDirection.captureSequence.map(\.id)).count, 52)
        XCTAssertEqual(CaptureDirection.captureSequence.first?.id, 20)
    }

    func testCaptureTargetOnlyAdvancesAfterCurrentTargetIsCaptured() {
        var tracker = CaptureProgressTracker(recordingType: .stationary)
        let first = CaptureDirection.captureSequence[0]
        let second = CaptureDirection.captureSequence[1]

        _ = tracker.update(
            position: .zero,
            yawRadians: first.yawRadians,
            pitchRadians: first.pitchRadians,
            trackingQuality: .normal,
            meshAnchorCount: 0,
            captureFrame: false
        )

        let observedAwayFromTarget = tracker.update(
            position: .zero,
            yawRadians: second.yawRadians,
            pitchRadians: second.pitchRadians,
            trackingQuality: .normal,
            meshAnchorCount: 0
        )
        XCTAssertNil(observedAwayFromTarget.capturedDirection)
        XCTAssertEqual(observedAwayFromTarget.state.currentDirectionID, first.id)

        let captured = capture(first, with: &tracker, at: .zero)
        XCTAssertEqual(captured.capturedDirection?.id, first.id)
        XCTAssertEqual(captured.state.currentDirectionID, second.id)
    }

    func testStationaryCaptureCompletesOnlyAfterAllSphericalTargets() {
        var tracker = CaptureProgressTracker(recordingType: .stationary)

        for direction in CaptureDirection.captureSequence.dropLast() {
            XCTAssertFalse(capture(direction, with: &tracker, at: .zero).didComplete)
        }
        XCTAssertEqual(tracker.state.missingDirectionCount, 1)

        let finalUpdate = capture(CaptureDirection.captureSequence.last!, with: &tracker, at: .zero)
        XCTAssertTrue(finalUpdate.didComplete)
        XCTAssertEqual(finalUpdate.state.motionPhase, .complete)
        XCTAssertEqual(finalUpdate.state.overallCoverage, 1)
    }

    func testStationaryCaptureWaitsForSuccessfullyEncodedFrame() {
        var tracker = CaptureProgressTracker(recordingType: .stationary)
        let direction = CaptureDirection.captureSequence[0]

        let observation = tracker.update(
            position: .zero,
            yawRadians: direction.yawRadians,
            pitchRadians: direction.pitchRadians,
            trackingQuality: .normal,
            meshAnchorCount: 0,
            captureFrame: false
        )
        XCTAssertNil(observation.capturedDirection)
        XCTAssertTrue(observation.state.capturedDirectionIDs.isEmpty)

        let captured = capture(direction, with: &tracker, at: .zero)
        XCTAssertEqual(captured.capturedDirection?.id, direction.id)
        XCTAssertEqual(captured.state.capturedDirectionIDs, [direction.id])
    }

    func testCaptureRequiresPortraitPhoneOrientation() {
        var tracker = CaptureProgressTracker(recordingType: .stationary)
        let direction = CaptureDirection.captureSequence[0]

        let rejected = tracker.update(
            position: .zero,
            yawRadians: direction.yawRadians,
            pitchRadians: direction.pitchRadians,
            trackingQuality: .normal,
            meshAnchorCount: 0,
            isPortraitCaptureOrientation: false
        )

        XCTAssertNil(rejected.capturedDirection)
        XCTAssertTrue(rejected.state.guidance.contains("竖直握持"))
    }

    func testFirstCameraHeadingBecomesTheLocalPanoramaFront() {
        let heading: Float = 1.1
        var tracker = CaptureProgressTracker(recordingType: .stationary)
        _ = tracker.update(
            position: .zero,
            yawRadians: heading,
            pitchRadians: 0,
            trackingQuality: .normal,
            meshAnchorCount: 0,
            captureFrame: false
        )
        let firstTarget = CaptureDirection.captureSequence[0]
        let captured = tracker.update(
            position: .zero,
            yawRadians: heading + firstTarget.yawRadians,
            pitchRadians: firstTarget.pitchRadians,
            trackingQuality: .normal,
            meshAnchorCount: 0
        )

        XCTAssertEqual(captured.capturedDirection?.id, firstTarget.id)
        XCTAssertEqual(
            captured.state.activeViewpointHeadingRadians,
            heading,
            accuracy: 0.001
        )
    }

    func testStationaryCaptureRejectsFrameAwayFromPoint() {
        var tracker = CaptureProgressTracker(recordingType: .stationary)
        _ = capture(CaptureDirection.captureSequence[0], with: &tracker, at: .zero)
        let direction = CaptureDirection.captureSequence[1]
        let update = tracker.update(
            position: Vector3(x: 0.7, y: 0, z: 0),
            yawRadians: direction.yawRadians,
            pitchRadians: direction.pitchRadians,
            trackingQuality: .normal,
            meshAnchorCount: 0
        )

        XCTAssertNil(update.capturedDirection)
        XCTAssertEqual(update.state.capturedDirectionIDs.count, 1)
        XCTAssertTrue(update.state.guidance.contains("手机移回原点"))
    }

    func testStationaryCaptureRejectsSmallHandheldParallaxDrift() {
        var tracker = CaptureProgressTracker(recordingType: .stationary)
        _ = capture(CaptureDirection.captureSequence[0], with: &tracker, at: .zero)
        let update = capture(
            CaptureDirection.captureSequence[1],
            with: &tracker,
            at: Vector3(
                x: CaptureProgressState.maximumCaptureDrift + 0.01,
                y: 0,
                z: 0
            )
        )

        XCTAssertNil(update.capturedDirection)
        XCTAssertEqual(update.state.capturedDirectionIDs.count, 1)
        XCTAssertTrue(update.state.guidance.contains("手机移回原点"))
    }

    func testMotionStabilityRequiresSustainedStillness() {
        var stability = CaptureMotionStabilityTracker()
        let forward = Vector3(x: 0, y: 0, z: 1)
        var result = stability.update(
            timestamp: 0,
            position: .zero,
            forward: forward
        )
        for index in 1...20 {
            result = stability.update(
                timestamp: Double(index) * 0.02,
                position: Vector3(x: Float(index % 2) * 0.0001, y: 0, z: 0),
                forward: forward
            )
        }
        XCTAssertTrue(result.isReady)

        result = stability.update(
            timestamp: 0.42,
            position: Vector3(x: 0.04, y: 0, z: 0),
            forward: forward
        )
        XCTAssertFalse(result.isReady)
        XCTAssertGreaterThan(
            result.linearSpeed,
            CaptureMotionStabilityTracker.maximumLinearSpeed
        )
    }

    func testFixedPointTourRequiresMovementAndCompletesThreePanoramas() {
        var tracker = CaptureProgressTracker(recordingType: .fixedPointTour)
        scanSphere(with: &tracker, at: .zero)
        XCTAssertEqual(tracker.state.motionPhase, .movingToNextPoint)

        let tooClose = capture(
            CaptureDirection.all[0],
            with: &tracker,
            at: Vector3(x: 0.5, y: 0, z: 0)
        )
        XCTAssertEqual(tooClose.state.motionPhase, .movingToNextPoint)
        XCTAssertNil(tooClose.capturedDirection)

        scanSphere(with: &tracker, at: Vector3(x: 1.1, y: 0, z: 0))
        XCTAssertEqual(tracker.state.motionPhase, .movingToNextPoint)
        scanSphere(with: &tracker, at: Vector3(x: 2.2, y: 0, z: 0))

        XCTAssertEqual(tracker.state.motionPhase, .complete)
        XCTAssertEqual(tracker.state.completedViewpoints, 3)
        XCTAssertEqual(tracker.state.viewpointPositions.count, 3)
        XCTAssertEqual(tracker.state.overallCoverage, 1)
    }

    func testRenderingRejectsDuplicateDirectionSet() async throws {
        let root = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var frames = try makeSphericalFrames()
        frames[51] = frames[0]

        do {
            _ = try await SceneRenderingService(rootURL: root, panoramaWidth: 512).render(
                sceneID: UUID(),
                recordingType: .stationary,
                frames: frames
            ) { _, _ in }
            XCTFail("重复方向不应生成全景")
        } catch SceneRenderingError.insufficientFrames {
            // Expected.
        }
    }

    func testRenderingDetectsVerticalDirectionFromRecordedPitch() throws {
        let frames = try makeSphericalFrames()
        XCTAssertEqual(
            SceneRenderingService.detectVerticalDirectionSign(in: frames),
            1
        )

        let reversedPitchFrames = frames.map { frame in
            var reversed = frame
            reversed.pitchDegrees *= -1
            return reversed
        }
        XCTAssertEqual(
            SceneRenderingService.detectVerticalDirectionSign(in: reversedPitchFrames),
            -1
        )
    }

    func testRenderingRecoversTheStartingHeadingAsPanoramaFront() throws {
        let heading: Float = 47 * .pi / 180
        let frames = try makeSphericalFrames().map { frame in
            var shifted = frame
            shifted.yawDegrees += heading * 180 / .pi
            return shifted
        }

        XCTAssertEqual(
            SceneRenderingService.forwardHeadingRadians(in: frames),
            heading,
            accuracy: 0.001
        )
    }

    func testRenderingUsesRobustViewpointCenterAndPenalizesParallax() throws {
        var frames = try makeSphericalFrames()
        for index in frames.indices {
            frames[index].position = Vector3(x: Float(index % 3) * 0.01, y: 0, z: 0)
        }
        frames[0].position = Vector3(x: 0.9, y: 0, z: 0)

        let center = SceneRenderingService.robustViewpointCenter(in: frames)
        XCTAssertEqual(center.x, 0.01, accuracy: 0.001)
        XCTAssertGreaterThan(
            SceneRenderingService.parallaxQualityWeight(
                framePosition: center,
                viewpointCenter: center
            ),
            SceneRenderingService.parallaxQualityWeight(
                framePosition: Vector3(x: 0.1, y: 0, z: 0),
                viewpointCenter: center
            )
        )
    }

    func testRenderingWritesNonblankTwoToOnePanorama() async throws {
        let root = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sceneID = UUID()

        let rendered = try await SceneRenderingService(
            rootURL: root,
            panoramaWidth: 512
        ).render(
            sceneID: sceneID,
            recordingType: .stationary,
            frames: try makeSphericalFrames()
        ) { _, _ in }

        XCTAssertEqual(rendered.viewpoints.count, 1)
        XCTAssertEqual(rendered.frameCount, 52)
        let panoramaPath = try XCTUnwrap(rendered.viewpoints.first?.panoramaPath)
        let panoramaURL = root
            .appendingPathComponent(sceneID.uuidString)
            .appendingPathComponent(panoramaPath)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(panoramaURL as CFURL, nil))
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        XCTAssertEqual(properties[kCGImagePropertyPixelWidth] as? Int, 512)
        XCTAssertEqual(properties[kCGImagePropertyPixelHeight] as? Int, 256)

        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let bytes = try rgbaBytes(from: image)
        var coloredPixels = 0
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let brightness = Int(bytes[index])
                + Int(bytes[index + 1])
                + Int(bytes[index + 2])
            if brightness > 24 {
                coloredPixels += 1
            }
        }
        XCTAssertGreaterThan(coloredPixels, image.width * image.height / 2)
        for y in [0, 1, image.height - 2, image.height - 1] {
            let coloredEdgePixels = (0..<image.width).reduce(into: 0) { count, x in
                let index = (y * image.width + x) * 4
                let brightness = Int(bytes[index])
                    + Int(bytes[index + 1])
                    + Int(bytes[index + 2])
                if brightness > 24 {
                    count += 1
                }
            }
            XCTAssertGreaterThan(
                coloredEdgePixels,
                image.width * 9 / 10,
                "全景顶部和底部不应出现未覆盖的黑边"
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(sceneID.uuidString)
                .appendingPathComponent("rendered/scene.json").path
        ))
    }

    func testRenderingFeatherBlendsOverlappingFrames() async throws {
        let root = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sceneID = UUID()
        let frames = try makeSphericalFrames { direction in
            direction.id.isMultiple(of: 2)
                ? UIColor(red: 0.02, green: 0.01, blue: 0.03, alpha: 1)
                : UIColor(red: 0.98, green: 0.99, blue: 0.97, alpha: 1)
        }

        let rendered = try await SceneRenderingService(
            rootURL: root,
            panoramaWidth: 512
        ).render(
            sceneID: sceneID,
            recordingType: .stationary,
            frames: frames
        ) { _, _ in }

        let panoramaPath = try XCTUnwrap(rendered.viewpoints.first?.panoramaPath)
        let panoramaURL = root
            .appendingPathComponent(sceneID.uuidString)
            .appendingPathComponent(panoramaPath)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(panoramaURL as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let bytes = try rgbaBytes(from: image)
        var blendedPixels = 0
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let red = bytes[index]
            if (32...223).contains(red) {
                blendedPixels += 1
            }
        }

        XCTAssertGreaterThan(blendedPixels, image.width * image.height / 8)

        let preservedCenters = CaptureDirection.all.reduce(into: 0) { count, direction in
            let normalizedYaw = (direction.yawRadians + .pi) / (2 * .pi)
            let normalizedPitch = 0.5 - direction.pitchRadians / .pi
            let x = min(max(Int(normalizedYaw * Float(image.width)), 0), image.width - 1)
            let y = min(max(Int(normalizedPitch * Float(image.height)), 0), image.height - 1)
            let red = bytes[(y * image.width + x) * 4]
            let matchesSource = direction.id.isMultiple(of: 2) ? red < 64 : red > 191
            if matchesSource {
                count += 1
            }
        }
        XCTAssertGreaterThanOrEqual(
            preservedCenters,
            CaptureDirection.all.count * 3 / 4
        )
    }

    @MainActor
    func testRepositoryPersistsNewPanoramaPath() throws {
        let root = makeTemporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = "rendered/viewpoint-00/panorama.jpg"
        let rendered = RenderedScene(
            generationState: .ready,
            generatedAt: .now,
            viewpoints: [RenderedViewpoint(
                id: UUID(), index: 0, name: "点位 1", position: .zero,
                panoramaPath: path, sourceFrameCount: 52
            )],
            thumbnailPath: path
        )
        let scene = SpatialScene(
            name: "可重启场景",
            capture: CaptureSummary(
                duration: 20, meshAnchorCount: 0, supportsLiDAR: false,
                trackingQuality: .normal, capturedFrameCount: 52,
                viewpointCount: 1, coverage: 1
            ),
            recordingType: .stationary,
            modelVersion: "equirectangular-v1",
            renderedScene: rendered
        )
        let storeURL = root.appendingPathComponent("scenes.json")
        let repository = SceneRepository(storeURL: storeURL)
        try repository.add(scene)
        let reloaded = SceneRepository(storeURL: storeURL)

        XCTAssertEqual(
            reloaded.scenes.first?.renderedScene?.viewpoints.first?.panoramaPath,
            path
        )
        XCTAssertNil(reloaded.lastError)
    }

    private func capture(
        _ direction: CaptureDirection,
        with tracker: inout CaptureProgressTracker,
        at position: Vector3
    ) -> CaptureProgressTracker.Update {
        tracker.update(
            position: position,
            yawRadians: direction.yawRadians,
            pitchRadians: direction.pitchRadians,
            trackingQuality: .normal,
            meshAnchorCount: 0
        )
    }

    private func scanSphere(with tracker: inout CaptureProgressTracker, at position: Vector3) {
        for direction in CaptureDirection.captureSequence {
            _ = capture(direction, with: &tracker, at: position)
        }
    }

    private func makeTemporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func makeSphericalFrames(
        colorForDirection: ((CaptureDirection) -> UIColor)? = nil
    ) throws -> [CapturedFramePayload] {
        try CaptureDirection.all.map { direction in
            let color = colorForDirection?(direction) ?? UIColor(
                hue: CGFloat(direction.id) / CGFloat(CaptureDirection.all.count),
                saturation: 0.8,
                brightness: 0.9,
                alpha: 1
            )
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(
                size: CGSize(width: 64, height: 48),
                format: format
            ).image { context in
                color.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
            }
            return CapturedFramePayload(
                viewpointIndex: 0,
                directionID: direction.id,
                yawDegrees: direction.yawDegrees,
                pitchDegrees: direction.pitchDegrees,
                position: .zero,
                calibration: CameraCalibration(
                    cameraTransform: cameraTransform(
                        yaw: direction.yawRadians,
                        pitch: direction.pitchRadians
                    ),
                    intrinsics: [32, 32, 32, 24],
                    imageWidth: 64,
                    imageHeight: 48
                ),
                imageData: try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
            )
        }
    }

    private func cameraTransform(yaw: Float, pitch: Float) -> [Float] {
        let forward = SIMD3<Float>(
            cos(pitch) * sin(yaw),
            sin(pitch),
            cos(pitch) * cos(yaw)
        )
        let backward = -forward
        let referenceUp = abs(backward.y) > 0.99
            ? SIMD3<Float>(0, 0, 1)
            : SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(referenceUp, backward))
        let up = simd_normalize(simd_cross(backward, right))
        return [
            right.x, right.y, right.z, 0,
            up.x, up.y, up.z, 0,
            backward.x, backward.y, backward.z, 0,
            0, 0, 0, 1
        ]
    }

    private func rgbaBytes(from image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(
            data: &bytes,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }
}
