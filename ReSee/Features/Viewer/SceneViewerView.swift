import CoreMotion
import ImageIO
import SceneKit
import SwiftUI
import UIKit

struct SceneViewerView: View {
    let scene: SpatialScene

    @State private var viewpointIndex = 0
    @State private var isPresentingLandscape = false
    @State private var isHorizontallyInverted = false
    @State private var isVerticallyInverted = false
    @State private var resetToken = 0

    private var renderedScene: RenderedScene? { scene.renderedScene }

    private var activeViewpoint: RenderedViewpoint? {
        guard let viewpoints = renderedScene?.viewpoints,
              viewpoints.indices.contains(viewpointIndex) else { return nil }
        return viewpoints[viewpointIndex]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if renderedScene?.generationState == .ready, let activeViewpoint {
                    panoramaViewer(viewpoint: activeViewpoint)
                    if (renderedScene?.viewpoints.count ?? 0) > 1 {
                        viewpointPicker
                    }
                } else {
                    unavailablePlaceholder
                }

                summaryGrid
                annotationSection
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle(scene.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $isPresentingLandscape) {
            if let activeViewpoint {
                LandscapePanoramaView(
                    title: scene.name,
                    viewpointName: activeViewpoint.name,
                    imageURL: panoramaURL(for: activeViewpoint),
                    isHorizontallyInverted: $isHorizontallyInverted,
                    isVerticallyInverted: $isVerticallyInverted
                )
            }
        }
        .onAppear {
            AppOrientationController.request(.portrait)
        }
    }

    private func panoramaViewer(viewpoint: RenderedViewpoint) -> some View {
        ZStack {
            PanoramaSceneView(
                imageURL: panoramaURL(for: viewpoint),
                interactionMode: .touch,
                resetToken: resetToken,
                isHorizontallyInverted: isHorizontallyInverted,
                isVerticallyInverted: isVerticallyInverted
            )

            VStack {
                HStack(spacing: 8) {
                    Label("360°", systemImage: "view.360")
                        .foregroundStyle(.white)
                    Spacer()
                    Text(viewpoint.name)
                        .foregroundStyle(.white.opacity(0.86))
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(.black.opacity(0.42))

                Spacer()

                HStack(spacing: 10) {
                    viewerButton(
                        systemImage: "arrow.counterclockwise",
                        accessibilityLabel: "复位视角"
                    ) {
                        resetToken += 1
                    }

                    Spacer()

                    viewerButton(
                        systemImage: "arrow.left.and.right",
                        accessibilityLabel: "左右翻转全景"
                    ) {
                        isHorizontallyInverted.toggle()
                    }

                    viewerButton(
                        systemImage: "arrow.up.and.down",
                        accessibilityLabel: "上下翻转全景"
                    ) {
                        isVerticallyInverted.toggle()
                    }

                    viewerButton(
                        systemImage: "rectangle.landscape.rotate",
                        accessibilityLabel: "横屏预览"
                    ) {
                        isPresentingLandscape = true
                    }
                }
                .padding(12)
            }
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .frame(maxHeight: 520)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.12))
        }
    }

    private func viewerButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(.black.opacity(0.5), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }

    private func panoramaURL(for viewpoint: RenderedViewpoint) -> URL {
        SceneAssetStore.url(sceneID: scene.id, relativePath: viewpoint.panoramaPath)
    }

    private var viewpointPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("切换全景点位")
                    .font(.headline)
                Spacer()
                Text("\(viewpointIndex + 1)/\(renderedScene?.viewpoints.count ?? 0)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                ForEach(
                    Array((renderedScene?.viewpoints ?? []).enumerated()),
                    id: \.element.id
                ) { index, viewpoint in
                    Button {
                        viewpointIndex = index
                        resetToken += 1
                    } label: {
                        VStack(spacing: 7) {
                            Text("\(index + 1)")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(index == viewpointIndex ? .white : .primary)
                                .frame(width: 38, height: 38)
                                .background(
                                    index == viewpointIndex ? AppTheme.accent : AppTheme.panel,
                                    in: Circle()
                                )
                            Text(viewpoint.name)
                                .font(.caption)
                                .foregroundStyle(
                                    index == viewpointIndex ? AppTheme.accent : .secondary
                                )
                        }
                    }
                    .buttonStyle(.plain)

                    if index < (renderedScene?.viewpoints.count ?? 0) - 1 {
                        Rectangle()
                            .fill(AppTheme.border)
                            .frame(height: 2)
                            .padding(.bottom, 21)
                    }
                }
            }
        }
        .padding(16)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border) }
    }

    private var unavailablePlaceholder: some View {
        ContentUnavailableView(
            "全景文件不可用",
            systemImage: "photo.badge.exclamationmark",
            description: Text("请重新记录并生成 360° 全景。")
        )
        .frame(height: 320)
        .frame(maxWidth: .infinity)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private var summaryGrid: some View {
        HStack(spacing: 12) {
            MetricCard(value: scene.recordingType.title, label: "记录方式")
            MetricCard(value: "\(scene.capture.viewpointCount)", label: "全景点位")
            MetricCard(value: "\(scene.capture.capturedFrameCount)", label: "合成画面")
        }
    }

    private var annotationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("空间标注").font(.title3.bold())
                Spacer()
                Text("\(scene.annotations.count)")
                    .foregroundStyle(.secondary)
            }

            if scene.annotations.isEmpty {
                Label("标注功能将在几何网格浏览阶段开放。", systemImage: "mappin.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border) }
            }
        }
    }
}

private struct LandscapePanoramaView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let viewpointName: String
    let imageURL: URL
    @Binding var isHorizontallyInverted: Bool
    @Binding var isVerticallyInverted: Bool

    @State private var interactionMode = PanoramaInteractionMode.touch
    @State private var resetToken = 0
    @State private var isMotionAvailable = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PanoramaSceneView(
                imageURL: imageURL,
                interactionMode: interactionMode,
                resetToken: resetToken,
                isHorizontallyInverted: isHorizontallyInverted,
                isVerticallyInverted: isVerticallyInverted,
                onMotionAvailabilityChanged: { available in
                    isMotionAvailable = available
                    if !available {
                        interactionMode = .touch
                    }
                }
            )
            .ignoresSafeArea()

            VStack {
                HStack(spacing: 12) {
                    landscapeButton(
                        systemImage: "xmark",
                        accessibilityLabel: "关闭横屏预览"
                    ) {
                        dismiss()
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                        Text(viewpointName)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    .foregroundStyle(.white)

                    Spacer()

                    modeControl

                    landscapeButton(
                        systemImage: "arrow.left.and.right",
                        accessibilityLabel: "左右翻转全景"
                    ) {
                        isHorizontallyInverted.toggle()
                    }

                    landscapeButton(
                        systemImage: "arrow.up.and.down",
                        accessibilityLabel: "上下翻转全景"
                    ) {
                        isVerticallyInverted.toggle()
                    }

                    landscapeButton(
                        systemImage: "arrow.counterclockwise",
                        accessibilityLabel: "复位视角"
                    ) {
                        resetToken += 1
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.black.opacity(0.46))

                Spacer()
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            AppOrientationController.request(.landscape)
        }
        .onDisappear {
            AppOrientationController.request(.portrait)
        }
    }

    private var modeControl: some View {
        HStack(spacing: 2) {
            modeButton(.touch, title: "触摸", systemImage: "hand.draw")
            modeButton(.motion, title: "跟随", systemImage: "gyroscope")
                .disabled(!isMotionAvailable)
                .opacity(isMotionAvailable ? 1 : 0.42)
        }
        .padding(3)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
    }

    private func modeButton(
        _ mode: PanoramaInteractionMode,
        title: String,
        systemImage: String
    ) -> some View {
        Button {
            interactionMode = mode
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(interactionMode == mode ? .black : .white)
                .padding(.horizontal, 11)
                .frame(height: 34)
                .background(
                    interactionMode == mode ? Color.white : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
        }
        .buttonStyle(.plain)
    }

    private func landscapeButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.5), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .help(accessibilityLabel)
    }
}

private enum PanoramaInteractionMode: Equatable {
    case touch
    case motion
}

private struct PanoramaSceneView: UIViewRepresentable {
    let imageURL: URL
    let interactionMode: PanoramaInteractionMode
    let resetToken: Int
    let isHorizontallyInverted: Bool
    let isVerticallyInverted: Bool
    var onMotionAvailabilityChanged: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onMotionAvailabilityChanged: onMotionAvailabilityChanged)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .black
        view.contentScaleFactor = UIScreen.main.scale
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        view.preferredFramesPerSecond = 60
        context.coordinator.configure(
            view: view,
            imageURL: imageURL,
            interactionMode: interactionMode,
            resetToken: resetToken,
            isHorizontallyInverted: isHorizontallyInverted,
            isVerticallyInverted: isVerticallyInverted
        )
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.update(
            view: view,
            imageURL: imageURL,
            interactionMode: interactionMode,
            resetToken: resetToken,
            isHorizontallyInverted: isHorizontallyInverted,
            isVerticallyInverted: isVerticallyInverted
        )
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.stopMotionUpdates()
        view.isPlaying = false
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let motionManager = CMMotionManager()
        private let onMotionAvailabilityChanged: (Bool) -> Void
        private weak var cameraNode: SCNNode?
        private weak var sceneView: SCNView?
        private weak var panGesture: UIPanGestureRecognizer?
        private var currentURL: URL?
        private var interactionMode = PanoramaInteractionMode.touch
        private var isHorizontallyInverted = false
        private var isVerticallyInverted = false
        private var lastResetToken = 0
        private var motionReference: CMAttitude?
        private var motionBaseYaw: Float = 0
        private var motionBasePitch: Float = 0
        private var yaw: Float = 0
        private var pitch: Float = 0

        init(onMotionAvailabilityChanged: @escaping (Bool) -> Void) {
            self.onMotionAvailabilityChanged = onMotionAvailabilityChanged
        }

        func configure(
            view: SCNView,
            imageURL: URL,
            interactionMode: PanoramaInteractionMode,
            resetToken: Int,
            isHorizontallyInverted: Bool,
            isVerticallyInverted: Bool
        ) {
            let scene = SCNScene()
            let sphere = SCNSphere(radius: 10)
            sphere.segmentCount = 512
            sphere.isGeodesic = false

            let material = SCNMaterial()
            material.isDoubleSided = true
            material.cullMode = .front
            material.lightingModel = .constant
            material.diffuse.wrapS = .repeat
            material.diffuse.wrapT = .clamp
            material.diffuse.magnificationFilter = .linear
            material.diffuse.minificationFilter = .linear
            material.diffuse.mipFilter = .linear
            material.diffuse.maxAnisotropy = 16
            sphere.firstMaterial = material

            // Front-face culling exposes the sphere interior. Reflecting the node here would
            // reverse the longitude direction already established by the panorama renderer.
            let sphereNode = SCNNode(geometry: sphere)
            scene.rootNode.addChildNode(sphereNode)

            let camera = SCNCamera()
            camera.fieldOfView = 64
            camera.zNear = 0.01
            camera.zFar = 100
            let cameraNode = SCNNode()
            cameraNode.camera = camera
            scene.rootNode.addChildNode(cameraNode)

            self.cameraNode = cameraNode
            sceneView = view
            view.scene = scene
            view.pointOfView = cameraNode
            installGestures(on: view)
            updateImageIfNeeded(imageURL, in: view)
            updateTextureOrientation(
                horizontallyInverted: isHorizontallyInverted,
                verticallyInverted: isVerticallyInverted,
                in: view
            )
            lastResetToken = resetToken
            setInteractionMode(interactionMode)
            reportMotionAvailability(motionManager.isDeviceMotionAvailable)
        }

        func update(
            view: SCNView,
            imageURL: URL,
            interactionMode: PanoramaInteractionMode,
            resetToken: Int,
            isHorizontallyInverted: Bool,
            isVerticallyInverted: Bool
        ) {
            updateImageIfNeeded(imageURL, in: view)
            if self.isHorizontallyInverted != isHorizontallyInverted
                || self.isVerticallyInverted != isVerticallyInverted {
                updateTextureOrientation(
                    horizontallyInverted: isHorizontallyInverted,
                    verticallyInverted: isVerticallyInverted,
                    in: view
                )
            }
            if self.interactionMode != interactionMode {
                setInteractionMode(interactionMode)
            }
            if lastResetToken != resetToken {
                lastResetToken = resetToken
                resetView(animated: true)
            }
        }

        func stopMotionUpdates() {
            motionManager.stopDeviceMotionUpdates()
            motionReference = nil
        }

        private func updateImageIfNeeded(_ imageURL: URL, in view: SCNView) {
            guard currentURL != imageURL else { return }
            currentURL = imageURL
            guard let material = view.scene?.rootNode.childNodes.first?
                .geometry?.firstMaterial else { return }
            let options = [
                kCGImageSourceShouldCache: true,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, options),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, options) else { return }
            material.diffuse.contents = image
        }

        private func updateTextureOrientation(
            horizontallyInverted: Bool,
            verticallyInverted: Bool,
            in view: SCNView
        ) {
            isHorizontallyInverted = horizontallyInverted
            isVerticallyInverted = verticallyInverted
            guard let material = view.scene?.rootNode.childNodes.first?
                .geometry?.firstMaterial else { return }
            let horizontalScale: Float = horizontallyInverted ? -1 : 1
            let verticalScale: Float = verticallyInverted ? 1 : -1
            var transform = SCNMatrix4MakeScale(horizontalScale, verticalScale, 1)
            transform.m41 = horizontallyInverted ? 1 : 0
            transform.m42 = verticallyInverted ? 0 : 1
            material.diffuse.contentsTransform = transform
        }

        private func installGestures(on view: SCNView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
            pan.delegate = self
            view.addGestureRecognizer(pan)
            panGesture = pan

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
            pinch.delegate = self
            view.addGestureRecognizer(pinch)

            let doubleTap = UITapGestureRecognizer(
                target: self,
                action: #selector(handleDoubleTap)
            )
            doubleTap.numberOfTapsRequired = 2
            view.addGestureRecognizer(doubleTap)
        }

        private func setInteractionMode(_ mode: PanoramaInteractionMode) {
            interactionMode = mode
            panGesture?.isEnabled = mode == .touch
            if mode == .motion {
                startMotionUpdates()
            } else {
                stopMotionUpdates()
            }
        }

        private func startMotionUpdates() {
            guard motionManager.isDeviceMotionAvailable else {
                interactionMode = .touch
                panGesture?.isEnabled = true
                reportMotionAvailability(false)
                return
            }
            motionBaseYaw = yaw
            motionBasePitch = pitch
            motionReference = nil
            motionManager.deviceMotionUpdateInterval = 1 / 60
            motionManager.startDeviceMotionUpdates(
                using: .xArbitraryCorrectedZVertical,
                to: .main
            ) { [weak self] motion, _ in
                self?.apply(motion: motion)
            }
        }

        private func apply(motion: CMDeviceMotion?) {
            guard interactionMode == .motion, let attitude = motion?.attitude else { return }
            guard let reference = motionReference else {
                motionReference = attitude.copy() as? CMAttitude
                return
            }
            guard let relative = attitude.copy() as? CMAttitude else { return }
            relative.multiply(byInverseOf: reference)

            let orientation = sceneView?.window?.windowScene?.interfaceOrientation
            let verticalSign: Float = orientation == .landscapeRight ? -1 : 1
            yaw = motionBaseYaw - Float(relative.yaw)
            pitch = motionBasePitch + Float(relative.roll) * verticalSign
            pitch = min(max(pitch, -.pi / 2 + 0.04), .pi / 2 - 0.04)
            cameraNode?.eulerAngles = SCNVector3(pitch, yaw, 0)
        }

        private func reportMotionAvailability(_ isAvailable: Bool) {
            DispatchQueue.main.async { [onMotionAvailabilityChanged] in
                onMotionAvailabilityChanged(isAvailable)
            }
        }

        @objc private func pan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            yaw -= Float(translation.x) * 0.004
            pitch -= Float(translation.y) * 0.004
            pitch = min(max(pitch, -.pi / 2 + 0.04), .pi / 2 - 0.04)
            cameraNode?.eulerAngles = SCNVector3(pitch, yaw, 0)
            gesture.setTranslation(.zero, in: gesture.view)
        }

        @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
            guard let camera = cameraNode?.camera else { return }
            camera.fieldOfView = min(max(camera.fieldOfView / gesture.scale, 28), 88)
            gesture.scale = 1
        }

        @objc private func handleDoubleTap() {
            resetView(animated: true)
        }

        private func resetView(animated: Bool) {
            stopMotionUpdates()
            yaw = 0
            pitch = 0
            SCNTransaction.begin()
            SCNTransaction.animationDuration = animated ? 0.22 : 0
            cameraNode?.eulerAngles = SCNVector3Zero
            cameraNode?.camera?.fieldOfView = 64
            SCNTransaction.commit()
            if interactionMode == .motion {
                startMotionUpdates()
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private struct MetricCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).stroke(AppTheme.border) }
    }
}
