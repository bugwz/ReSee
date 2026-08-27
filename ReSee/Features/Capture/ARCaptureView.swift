import ARKit
import CoreImage
import ImageIO
import RealityKit
import SwiftUI
import UIKit

struct ARCaptureView: UIViewRepresentable {
    let recordingType: RecordingType
    @Binding var progress: CaptureProgressState
    let onFrameCaptured: (CapturedFramePayload) -> Void
    let onCompleted: () -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            recordingType: recordingType,
            progress: $progress,
            onFrameCaptured: onFrameCaptured,
            onCompleted: onCompleted,
            onError: onError
        )
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false
        view.session.delegateQueue = context.coordinator.sessionQueue
        view.session.delegate = context.coordinator
        view.renderOptions.insert(.disableMotionBlur)

        guard ARWorldTrackingConfiguration.isSupported else {
            DispatchQueue.main.async {
                context.coordinator.reportUnsupportedDevice()
            }
            return view
        }

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        configuration.environmentTexturing = .automatic
        if let highResolutionFormat = ARWorldTrackingConfiguration
            .recommendedVideoFormatForHighResolutionFrameCapturing {
            configuration.videoFormat = highResolutionFormat
        } else if let format4K = ARWorldTrackingConfiguration
            .recommendedVideoFormatFor4KResolution {
            configuration.videoFormat = format4K
        }

        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) {
            configuration.sceneReconstruction = .meshWithClassification
            view.debugOptions.insert(.showSceneUnderstanding)
        } else if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            configuration.sceneReconstruction = .mesh
            view.debugOptions.insert(.showSceneUnderstanding)
        }

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {}

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        let sessionQueue = DispatchQueue(
            label: "com.dabble.resee.capture-session",
            qos: .userInitiated
        )

        private var progress: Binding<CaptureProgressState>
        private let onFrameCaptured: (CapturedFramePayload) -> Void
        private let onCompleted: () -> Void
        private let onError: (String) -> Void
        private let imageContext = CIContext(options: [.cacheIntermediates: false])
        private var tracker: CaptureProgressTracker
        private var lastUpdate = Date.distantPast
        private var hasCompleted = false
        private var isCapturingHighResolutionFrame = false
        private var motionStabilityTracker = CaptureMotionStabilityTracker()
        private var latestStability = CaptureMotionStabilityTracker.Result(
            linearSpeed: 0,
            angularSpeed: 0,
            stableDuration: 0,
            isReady: false
        )
        private var captureCandidates: [ARFrame] = []

        init(
            recordingType: RecordingType,
            progress: Binding<CaptureProgressState>,
            onFrameCaptured: @escaping (CapturedFramePayload) -> Void,
            onCompleted: @escaping () -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.progress = progress
            self.onFrameCaptured = onFrameCaptured
            self.onCompleted = onCompleted
            self.onError = onError
            tracker = CaptureProgressTracker(
                recordingType: recordingType,
                supportsLiDAR: ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
            )
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            let transform = frame.camera.transform
            let position = Vector3(
                x: transform.columns.3.x,
                y: transform.columns.3.y,
                z: transform.columns.3.z
            )
            let forward = -transform.columns.2
            latestStability = motionStabilityTracker.update(
                timestamp: frame.timestamp,
                position: position,
                forward: Vector3(x: forward.x, y: forward.y, z: forward.z),
                up: Vector3(
                    x: transform.columns.1.x,
                    y: transform.columns.1.y,
                    z: transform.columns.1.z
                )
            )

            guard !hasCompleted, Date.now.timeIntervalSince(lastUpdate) > 0.18 else { return }
            lastUpdate = .now

            let quality = frame.camera.trackingState.captureQuality
            let yaw = atan2(forward.x, forward.z)
            let pitch = asin(min(max(forward.y, -1), 1))
            let viewpointIndex = tracker.state.activeViewpointIndex

            let update = tracker.update(
                position: position,
                yawRadians: yaw,
                pitchRadians: pitch,
                trackingQuality: quality,
                meshAnchorCount: frame.anchors.lazy.filter { $0 is ARMeshAnchor }.count,
                isStableForCapture: latestStability.isReady,
                captureFrame: false
            )

            let pendingDirectionID = update.state.currentDirectionID
            let pendingDirection = pendingDirectionID.flatMap { id in
                CaptureDirection.all.first { $0.id == id }
            }
            let shouldCapture = quality == .normal
                && update.state.motionPhase == .scanning
                && update.state.distanceFromActivePoint
                    <= CaptureProgressState.maximumCaptureDrift
                && latestStability.isReady
                && pendingDirection.map {
                    CaptureDirection.angularDistance(
                        fromYaw: yaw,
                        pitch: pitch,
                        to: $0
                    ) <= 14 * .pi / 180
                } == true
                && !update.state.capturedDirectionIDs.contains(pendingDirectionID ?? -1)
                && !isCapturingHighResolutionFrame

            if shouldCapture, let pendingDirection {
                requestHighResolutionFrame(
                    from: session,
                    expectedDirection: pendingDirection,
                    viewpointIndex: viewpointIndex
                )
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                progress.wrappedValue = update.state
            }
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                progress.wrappedValue.trackingQuality = .unavailable
                onError("AR 空间记录无法继续：\(error.localizedDescription)")
            }
        }

        func sessionWasInterrupted(_ session: ARSession) {
            DispatchQueue.main.async { [weak self] in
                self?.progress.wrappedValue.trackingQuality = .limited
            }
        }

        func sessionInterruptionEnded(_ session: ARSession) {
            lastUpdate = .distantPast
            motionStabilityTracker.reset()
        }

        func reportUnsupportedDevice() {
            progress.wrappedValue.trackingQuality = .unavailable
            onError("这台设备不支持 AR 世界跟踪，暂时无法进行空间记录。")
        }

        private func requestHighResolutionFrame(
            from session: ARSession,
            expectedDirection: CaptureDirection,
            viewpointIndex: Int
        ) {
            isCapturingHighResolutionFrame = true
            captureCandidates = []
            requestCaptureCandidate(
                from: session,
                expectedDirection: expectedDirection,
                viewpointIndex: viewpointIndex
            )
        }

        private func requestCaptureCandidate(
            from session: ARSession,
            expectedDirection: CaptureDirection,
            viewpointIndex: Int
        ) {
            session.captureHighResolutionFrame { [weak self, weak session] frame, _ in
                guard let self else { return }
                sessionQueue.async { [weak self] in
                    self?.handleCaptureCandidate(
                        frame,
                        session: session,
                        expectedDirection: expectedDirection,
                        viewpointIndex: viewpointIndex
                    )
                }
            }
        }

        private func handleCaptureCandidate(
            _ frame: ARFrame?,
            session: ARSession?,
            expectedDirection: CaptureDirection,
            viewpointIndex: Int
        ) {
            guard !hasCompleted,
                  let frame,
                  let session,
                  frame.camera.trackingState.captureQuality == .normal,
                  latestStability.isReady,
                  tracker.state.activeViewpointIndex == viewpointIndex,
                  tracker.state.currentDirectionID == expectedDirection.id else {
                cancelPendingCapture()
                return
            }

            let transform = frame.camera.transform
            let position = Vector3(
                x: transform.columns.3.x,
                y: transform.columns.3.y,
                z: transform.columns.3.z
            )
            let forward = -transform.columns.2
            let yaw = atan2(forward.x, forward.z)
            let pitch = asin(min(max(forward.y, -1), 1))
            guard CaptureDirection.angularDistance(
                fromYaw: yaw,
                pitch: pitch,
                to: expectedDirection
            ) <= 14 * .pi / 180,
            position.distance(to: tracker.state.viewpointPositions[viewpointIndex])
                <= CaptureProgressState.maximumCaptureDrift else {
                cancelPendingCapture()
                return
            }

            captureCandidates.append(frame)
            if captureCandidates.count < 2 {
                requestCaptureCandidate(
                    from: session,
                    expectedDirection: expectedDirection,
                    viewpointIndex: viewpointIndex
                )
                return
            }

            let selectedFrame = captureCandidates.max { lhs, rhs in
                sharpnessScore(from: lhs.capturedImage)
                    < sharpnessScore(from: rhs.capturedImage)
            } ?? frame
            captureCandidates = []
            finishHighResolutionCapture(
                selectedFrame,
                expectedDirection: expectedDirection,
                viewpointIndex: viewpointIndex
            )
        }

        private func finishHighResolutionCapture(
            _ frame: ARFrame,
            expectedDirection: CaptureDirection,
            viewpointIndex: Int
        ) {
            isCapturingHighResolutionFrame = false
            let transform = frame.camera.transform
            let position = Vector3(
                x: transform.columns.3.x,
                y: transform.columns.3.y,
                z: transform.columns.3.z
            )
            let forward = -transform.columns.2
            let yaw = atan2(forward.x, forward.z)
            let pitch = asin(min(max(forward.y, -1), 1))
            guard let imageData = makeImageData(from: frame.capturedImage) else {
                cancelPendingCapture()
                return
            }

            let update = tracker.update(
                position: position,
                yawRadians: yaw,
                pitchRadians: pitch,
                trackingQuality: .normal,
                meshAnchorCount: tracker.state.meshAnchorCount,
                isStableForCapture: true,
                captureFrame: true
            )
            guard let direction = update.capturedDirection else { return }
            let payload = CapturedFramePayload(
                viewpointIndex: viewpointIndex,
                directionID: direction.id,
                yawDegrees: yaw * 180 / .pi,
                pitchDegrees: pitch * 180 / .pi,
                position: position,
                calibration: CameraCalibration(
                    cameraTransform: [
                        transform.columns.0.x,
                        transform.columns.0.y,
                        transform.columns.0.z,
                        transform.columns.0.w,
                        transform.columns.1.x,
                        transform.columns.1.y,
                        transform.columns.1.z,
                        transform.columns.1.w,
                        transform.columns.2.x,
                        transform.columns.2.y,
                        transform.columns.2.z,
                        transform.columns.2.w,
                        transform.columns.3.x,
                        transform.columns.3.y,
                        transform.columns.3.z,
                        transform.columns.3.w
                    ],
                    intrinsics: [
                        frame.camera.intrinsics.columns.0.x,
                        frame.camera.intrinsics.columns.1.y,
                        frame.camera.intrinsics.columns.2.x,
                        frame.camera.intrinsics.columns.2.y
                    ],
                    imageWidth: CVPixelBufferGetWidth(frame.capturedImage),
                    imageHeight: CVPixelBufferGetHeight(frame.capturedImage)
                ),
                imageData: imageData
            )
            if update.didComplete {
                hasCompleted = true
            }
            motionStabilityTracker.reset()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                progress.wrappedValue = update.state
                onFrameCaptured(payload)
                if update.didComplete {
                    onCompleted()
                }
            }
        }

        private func cancelPendingCapture() {
            captureCandidates = []
            isCapturingHighResolutionFrame = false
            motionStabilityTracker.reset()
        }

        private func sharpnessScore(from pixelBuffer: CVPixelBuffer) -> Double {
            let source = CIImage(cvPixelBuffer: pixelBuffer)
            let targetWidth = 256
            let scale = CGFloat(targetWidth) / source.extent.width
            let targetHeight = max(Int((source.extent.height * scale).rounded()), 2)
            let scaled = source.transformed(
                by: CGAffineTransform(scaleX: scale, y: scale)
            )
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
                ?? CGColorSpaceCreateDeviceRGB()
            var pixels = [UInt8](
                repeating: 0,
                count: targetWidth * targetHeight * 4
            )
            pixels.withUnsafeMutableBytes { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                imageContext.render(
                    scaled,
                    toBitmap: baseAddress,
                    rowBytes: targetWidth * 4,
                    bounds: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
                    format: .RGBA8,
                    colorSpace: colorSpace
                )
            }

            var count = 0.0
            var mean = 0.0
            var sumOfSquares = 0.0
            for y in 1..<(targetHeight - 1) {
                for x in 1..<(targetWidth - 1) {
                    let center = luminance(pixels, x: x, y: y, width: targetWidth)
                    let laplacian = 4 * center
                        - luminance(pixels, x: x - 1, y: y, width: targetWidth)
                        - luminance(pixels, x: x + 1, y: y, width: targetWidth)
                        - luminance(pixels, x: x, y: y - 1, width: targetWidth)
                        - luminance(pixels, x: x, y: y + 1, width: targetWidth)
                    count += 1
                    let delta = laplacian - mean
                    mean += delta / count
                    sumOfSquares += delta * (laplacian - mean)
                }
            }
            return count > 1 ? sumOfSquares / (count - 1) : 0
        }

        private func luminance(
            _ pixels: [UInt8],
            x: Int,
            y: Int,
            width: Int
        ) -> Double {
            let index = (y * width + x) * 4
            return Double(pixels[index]) * 0.2126
                + Double(pixels[index + 1]) * 0.7152
                + Double(pixels[index + 2]) * 0.0722
        }

        private func makeImageData(from pixelBuffer: CVPixelBuffer) -> Data? {
            let source = CIImage(cvPixelBuffer: pixelBuffer)
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
                ?? CGColorSpaceCreateDeviceRGB()
            return imageContext.heifRepresentation(
                of: source,
                format: .RGBA8,
                colorSpace: colorSpace,
                options: [
                    kCGImageDestinationLossyCompressionQuality
                        as CIImageRepresentationOption: 0.98
                ]
            )
        }
    }
}

private extension ARCamera.TrackingState {
    var captureQuality: TrackingQuality {
        switch self {
        case .normal: .normal
        case .limited: .limited
        case .notAvailable: .unavailable
        }
    }
}
