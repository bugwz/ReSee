import ARKit
import CoreImage
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
        private var progress: Binding<CaptureProgressState>
        private let onFrameCaptured: (CapturedFramePayload) -> Void
        private let onCompleted: () -> Void
        private let onError: (String) -> Void
        private let imageContext = CIContext(options: [.cacheIntermediates: false])
        private var tracker: CaptureProgressTracker
        private var lastUpdate = Date.distantPast
        private var hasCompleted = false

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
            guard !hasCompleted, Date.now.timeIntervalSince(lastUpdate) > 0.18 else { return }
            lastUpdate = .now

            let quality = frame.camera.trackingState.captureQuality
            let transform = frame.camera.transform
            let position = Vector3(
                x: transform.columns.3.x,
                y: transform.columns.3.y,
                z: transform.columns.3.z
            )
            let forward = -transform.columns.2
            let yaw = atan2(forward.x, forward.z)
            let pitch = asin(min(max(forward.y, -1), 1))
            let viewpointIndex = tracker.state.activeViewpointIndex

            var update = tracker.update(
                position: position,
                yawRadians: yaw,
                pitchRadians: pitch,
                trackingQuality: quality,
                meshAnchorCount: frame.anchors.lazy.filter { $0 is ARMeshAnchor }.count,
                captureFrame: false
            )

            var payload: CapturedFramePayload?
            let pendingDirectionID = update.state.currentDirectionID
            let pendingDirection = pendingDirectionID.flatMap { id in
                CaptureDirection.all.first { $0.id == id }
            }
            let shouldCapture = quality == .normal
                && update.state.motionPhase == .scanning
                && update.state.distanceFromActivePoint <= 0.45
                && pendingDirection.map {
                    CaptureDirection.angularDistance(
                        fromYaw: yaw,
                        pitch: pitch,
                        to: $0
                    ) <= 14 * .pi / 180
                } == true
                && !update.state.capturedDirectionIDs.contains(pendingDirectionID ?? -1)

            if shouldCapture,
               let jpegData = makeJPEG(from: frame.capturedImage) {
                update = tracker.update(
                    position: position,
                    yawRadians: yaw,
                    pitchRadians: pitch,
                    trackingQuality: quality,
                    meshAnchorCount: update.state.meshAnchorCount,
                    captureFrame: true
                )
                if let direction = update.capturedDirection {
                    payload = CapturedFramePayload(
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
                        jpegData: jpegData
                    )
                }
            }

            if update.didComplete {
                hasCompleted = true
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                progress.wrappedValue = update.state
                if let payload {
                    onFrameCaptured(payload)
                }
                if update.didComplete {
                    onCompleted()
                }
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
        }

        func reportUnsupportedDevice() {
            progress.wrappedValue.trackingQuality = .unavailable
            onError("这台设备不支持 AR 世界跟踪，暂时无法进行空间记录。")
        }

        private func makeJPEG(from pixelBuffer: CVPixelBuffer) -> Data? {
            let source = CIImage(cvPixelBuffer: pixelBuffer)
            guard let cgImage = imageContext.createCGImage(source, from: source.extent) else {
                return nil
            }
            return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.88)
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
