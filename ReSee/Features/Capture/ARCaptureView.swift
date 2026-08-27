import ARKit
import CoreImage
import ImageIO
import RealityKit
import SwiftUI
import UIKit

final class CaptureTargetProjection: ObservableObject {
    @Published var position: CGPoint?
}

struct ARCaptureView: UIViewRepresentable {
    let recordingType: RecordingType
    @Binding var progress: CaptureProgressState
    let targetProjection: CaptureTargetProjection
    let isCaptureEnabled: Bool
    let onFrameCaptured: (CapturedFramePayload) -> Void
    let onCompleted: () -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            recordingType: recordingType,
            progress: $progress,
            targetProjection: targetProjection,
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
        configuration.worldAlignment = .gravity
        if let highResolutionFormat = ARWorldTrackingConfiguration
            .recommendedVideoFormatForHighResolutionFrameCapturing {
            configuration.videoFormat = highResolutionFormat
        } else if let format4K = ARWorldTrackingConfiguration
            .recommendedVideoFormatFor4KResolution {
            configuration.videoFormat = format4K
        }

        view.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.setCaptureEnabled(isCaptureEnabled)
        context.coordinator.setViewportSize(uiView.bounds.size)
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        let sessionQueue = DispatchQueue(
            label: "com.dabble.resee.capture-session",
            qos: .userInitiated
        )

        private var progress: Binding<CaptureProgressState>
        private let targetProjection: CaptureTargetProjection
        private let onFrameCaptured: (CapturedFramePayload) -> Void
        private let onCompleted: () -> Void
        private let onError: (String) -> Void
        private let recordingType: RecordingType
        private let supportsLiDAR: Bool
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
        private var isCaptureEnabled = false
        private var viewportSize: CGSize = .zero
        private var lastProjectionTimestamp: TimeInterval = 0
        private var requestedCaptureEnabled = false
        private var requestedViewportSize: CGSize = .zero

        init(
            recordingType: RecordingType,
            progress: Binding<CaptureProgressState>,
            targetProjection: CaptureTargetProjection,
            onFrameCaptured: @escaping (CapturedFramePayload) -> Void,
            onCompleted: @escaping () -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.progress = progress
            self.targetProjection = targetProjection
            self.recordingType = recordingType
            self.onFrameCaptured = onFrameCaptured
            self.onCompleted = onCompleted
            self.onError = onError
            supportsLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
            tracker = CaptureProgressTracker(
                recordingType: recordingType,
                supportsLiDAR: supportsLiDAR
            )
        }

        func setCaptureEnabled(_ enabled: Bool) {
            guard requestedCaptureEnabled != enabled else { return }
            requestedCaptureEnabled = enabled
            sessionQueue.async { [weak self] in
                guard let self, isCaptureEnabled != enabled else { return }
                isCaptureEnabled = enabled
                cancelPendingCapture()
                if enabled {
                    tracker = CaptureProgressTracker(
                        recordingType: recordingType,
                        supportsLiDAR: supportsLiDAR
                    )
                    hasCompleted = false
                    lastUpdate = .distantPast
                } else {
                    DispatchQueue.main.async { [weak self] in
                        self?.targetProjection.position = nil
                    }
                }
            }
        }

        func setViewportSize(_ size: CGSize) {
            guard requestedViewportSize != size else { return }
            requestedViewportSize = size
            sessionQueue.async { [weak self] in
                self?.viewportSize = size
            }
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

            if isCaptureEnabled,
               frame.timestamp - lastProjectionTimestamp >= 1.0 / 30.0 {
                lastProjectionTimestamp = frame.timestamp
                publishSpatialTarget(for: frame)
            }

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
                meshAnchorCount: 0,
                isStableForCapture: latestStability.isReady,
                captureFrame: false
            )

            let pendingDirectionID = update.state.currentDirectionID
            let pendingDirection = pendingDirectionID.flatMap { id in
                CaptureDirection.all.first { $0.id == id }
            }
            let shouldCapture = isCaptureEnabled
                && quality == .normal
                && update.state.motionPhase == .scanning
                && update.state.distanceFromActivePoint
                    <= update.state.allowedCaptureDrift
                && latestStability.isReady
                && pendingDirection.map {
                    $0.isAligned(
                        fromYaw: (
                            yaw - update.state.activeViewpointHeadingRadians
                        ).normalizedAngle,
                        pitch: pitch
                    )
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
            session.captureHighResolutionFrame { [weak self] frame, _ in
                guard let self else { return }
                sessionQueue.async { [weak self] in
                    self?.handleCaptureCandidate(
                        frame,
                        expectedDirection: expectedDirection,
                        viewpointIndex: viewpointIndex
                    )
                }
            }
        }

        private func handleCaptureCandidate(
            _ frame: ARFrame?,
            expectedDirection: CaptureDirection,
            viewpointIndex: Int
        ) {
            guard !hasCompleted,
                  isCaptureEnabled,
                  let frame,
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
            guard expectedDirection.isAligned(
                fromYaw: (
                    yaw - tracker.state.activeViewpointHeadingRadians
                ).normalizedAngle,
                pitch: pitch
            ),
            position.distance(to: tracker.state.viewpointPositions[viewpointIndex])
                <= (expectedDirection.isPolar
                    ? CaptureProgressState.maximumPolarCaptureDrift
                    : CaptureProgressState.maximumCaptureDrift) else {
                cancelPendingCapture()
                return
            }

            finishHighResolutionCapture(
                frame,
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
            let projectedPosition = projectedTargetPosition(
                for: frame,
                state: update.state
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
                targetProjection.position = projectedPosition
                onFrameCaptured(payload)
                if update.didComplete {
                    onCompleted()
                }
            }
        }

        private func cancelPendingCapture() {
            isCapturingHighResolutionFrame = false
            motionStabilityTracker.reset()
        }

        private func publishSpatialTarget(for frame: ARFrame) {
            let position = projectedTargetPosition(for: frame, state: tracker.state)
            DispatchQueue.main.async { [weak self] in
                self?.targetProjection.position = position
            }
        }

        private func projectedTargetPosition(
            for frame: ARFrame,
            state: CaptureProgressState
        ) -> CGPoint? {
            guard viewportSize.width > 0,
                  viewportSize.height > 0,
                  state.motionPhase == .scanning,
                  let target = state.currentTargetDirection,
                  state.viewpointPositions.indices.contains(state.activeViewpointIndex)
            else { return nil }
            let origin = state.viewpointPositions[state.activeViewpointIndex]

            let worldYaw = target.yawRadians + state.activeViewpointHeadingRadians
            let horizontal = cos(target.pitchRadians)
            let targetPoint = SIMD3<Float>(
                origin.x + horizontal * sin(worldYaw) * 4,
                origin.y + sin(target.pitchRadians) * 4,
                origin.z + horizontal * cos(worldYaw) * 4
            )
            let cameraPosition = SIMD3<Float>(
                frame.camera.transform.columns.3.x,
                frame.camera.transform.columns.3.y,
                frame.camera.transform.columns.3.z
            )
            let cameraForward = -SIMD3<Float>(
                frame.camera.transform.columns.2.x,
                frame.camera.transform.columns.2.y,
                frame.camera.transform.columns.2.z
            )
            let guideCenter = CGPoint(
                x: viewportSize.width / 2,
                y: viewportSize.height * 0.44
            )
            guard simd_dot(targetPoint - cameraPosition, cameraForward) > 0 else {
                let currentYaw = atan2(cameraForward.x, cameraForward.z)
                let currentPitch = asin(min(max(cameraForward.y, -1), 1))
                let yawDelta = (worldYaw - currentYaw).shortestSignedAngle
                let pitchDelta = target.pitchRadians - currentPitch
                return CGPoint(
                    x: guideCenter.x
                        + CGFloat(yawDelta / (55 * .pi / 180)) * viewportSize.width / 2,
                    y: guideCenter.y
                        - CGFloat(pitchDelta / (72 * .pi / 180)) * viewportSize.height / 2
                )
            }

            let projectedTarget = frame.camera.projectPoint(
                targetPoint,
                orientation: .portrait,
                viewportSize: viewportSize
            )
            let projectedCenter = frame.camera.projectPoint(
                cameraPosition + cameraForward * 4,
                orientation: .portrait,
                viewportSize: viewportSize
            )
            guard projectedTarget.x.isFinite,
                  projectedTarget.y.isFinite,
                  projectedCenter.x.isFinite,
                  projectedCenter.y.isFinite else { return nil }

            return CGPoint(
                x: guideCenter.x + projectedTarget.x - projectedCenter.x,
                y: guideCenter.y + projectedTarget.y - projectedCenter.y
            )
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
