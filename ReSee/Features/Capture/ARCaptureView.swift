import ARKit
import RealityKit
import SwiftUI

struct ARCaptureView: UIViewRepresentable {
    @Binding var metrics: CaptureMetrics

    func makeCoordinator() -> Coordinator {
        Coordinator(metrics: $metrics)
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.automaticallyConfigureSession = false
        view.session.delegate = context.coordinator
        view.renderOptions.insert(.disableMotionBlur)

        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
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
        private var metrics: Binding<CaptureMetrics>
        private var lastUpdate = Date.distantPast

        init(metrics: Binding<CaptureMetrics>) {
            self.metrics = metrics
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard Date.now.timeIntervalSince(lastUpdate) > 0.25 else { return }
            lastUpdate = .now

            let quality: TrackingQuality
            switch frame.camera.trackingState {
            case .normal:
                quality = .normal
            case .limited:
                quality = .limited
            case .notAvailable:
                quality = .unavailable
            }

            let meshCount = frame.anchors.lazy.filter { $0 is ARMeshAnchor }.count
            let newMetrics = CaptureMetrics(
                trackingQuality: quality,
                meshAnchorCount: meshCount,
                supportsLiDAR: ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
            )

            DispatchQueue.main.async { [weak self] in
                self?.metrics.wrappedValue = newMetrics
            }
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            DispatchQueue.main.async { [weak self] in
                self?.metrics.wrappedValue.trackingQuality = .unavailable
            }
        }
    }
}

