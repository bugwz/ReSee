import Metal
import MetalKit
import MetalSplatter
import simd
import SplatIO
import SwiftUI

struct GaussianSplatViewerView: View {
    let fileURL: URL

    @StateObject private var camera = SplatCameraController()
    @State private var loadState: SplatLoadState = .loading
    @State private var controlsVisible = true

    var body: some View {
        ZStack {
            Color.black
            GaussianMetalView(fileURL: fileURL, camera: camera) { state in
                loadState = state
            }

            if controlsVisible {
                controlOverlay
            }

            statusOverlay
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                Button {
                    camera.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                Button {
                    controlsVisible.toggle()
                } label: {
                    Image(systemName: controlsVisible ? "gamecontroller.fill" : "gamecontroller")
                }
            }
            .buttonStyle(SplatOverlayButtonStyle())
            .padding(12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Gaussian Splatting 自由空间查看器")
    }

    private var controlOverlay: some View {
        VStack {
            HStack {
                Label("6DoF", systemImage: "move.3d")
                Spacer()
                Text("MetalSplatter")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.82))
            .padding(12)
            Spacer()
            HStack(alignment: .bottom) {
                SplatJoystick(
                    title: "前后左右",
                    systemImage: "move.3d",
                    onChanged: camera.setMovement
                )
                Spacer()
                SplatJoystick(
                    title: "无级视角",
                    systemImage: "scope",
                    onChanged: camera.setLook
                )
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch loadState {
        case .loading:
            GaussianParticleLoadingView()
        case let .failed(message):
            ContentUnavailableView(
                "无法显示高斯场景",
                systemImage: "cube.transparent.fill",
                description: Text(message)
            )
            .foregroundStyle(.white)
            .padding()
        case .ready:
            EmptyView()
        }
    }
}

private enum SplatLoadState: Equatable {
    case loading
    case ready
    case failed(String)
}

enum SplatJoystickMapping {
    static func movement(_ screenVector: SIMD2<Float>) -> SIMD2<Float> {
        -screenVector
    }

    static func look(_ screenVector: SIMD2<Float>) -> SIMD2<Float> {
        -screenVector
    }
}

@MainActor
private final class SplatCameraController: ObservableObject {
    var position = SIMD3<Float>(0, 0, 8)
    var yaw: Float = 0
    var pitch: Float = 0
    private(set) var movement = SIMD2<Float>.zero
    private(set) var look = SIMD2<Float>.zero

    func setMovement(_ value: SIMD2<Float>) {
        // MTKView renders through an inverse view transform. Convert the
        // screen-space joystick vector once at the input boundary so dragging
        // toward a direction moves the visible viewpoint in that direction.
        movement = SplatJoystickMapping.movement(value)
    }

    func setLook(_ value: SIMD2<Float>) {
        // Keep free-look consistent with direct manipulation: dragging right
        // turns right and dragging up raises the view after view inversion.
        look = SplatJoystickMapping.look(value)
    }

    func reset() {
        position = SIMD3<Float>(0, 0, 8)
        yaw = 0
        pitch = 0
        movement = .zero
        look = .zero
    }

    func advance(by elapsed: Float) {
        let frameTime = min(max(elapsed, 0), 0.05)
        yaw += look.x * frameTime * 1.35
        pitch = min(max(pitch - look.y * frameTime * 1.2, -.pi * 0.48), .pi * 0.48)

        let forward = SIMD3<Float>(sin(yaw), 0, -cos(yaw))
        let right = SIMD3<Float>(cos(yaw), 0, sin(yaw))
        let speed: Float = 2.2
        position += (right * movement.x + forward * -movement.y) * speed * frameTime
    }

    var viewMatrix: simd_float4x4 {
        let translation = splatTranslation(-position.x, -position.y, -position.z)
        let yawRotation = splatRotation(radians: -yaw, axis: SIMD3<Float>(0, 1, 0))
        let pitchRotation = splatRotation(radians: -pitch, axis: SIMD3<Float>(1, 0, 0))
        let commonDatasetCalibration = splatRotation(
            radians: .pi,
            axis: SIMD3<Float>(0, 0, 1)
        )
        return pitchRotation * yawRotation * translation * commonDatasetCalibration
    }
}

private struct SplatJoystick: View {
    let title: String
    let systemImage: String
    let onChanged: (SIMD2<Float>) -> Void

    @State private var knobOffset = CGSize.zero

    private let radius: CGFloat = 48

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.46))
                    .overlay { Circle().stroke(.white.opacity(0.3), lineWidth: 1) }
                Image(systemName: "chevron.up")
                    .offset(y: -radius + 12)
                Image(systemName: "chevron.down")
                    .offset(y: radius - 12)
                Image(systemName: "chevron.left")
                    .offset(x: -radius + 12)
                Image(systemName: "chevron.right")
                    .offset(x: radius - 12)
                Circle()
                    .fill(.white.opacity(0.82))
                    .frame(width: 42, height: 42)
                    .overlay { Image(systemName: systemImage).foregroundStyle(.black.opacity(0.72)) }
                    .offset(knobOffset)
            }
            .frame(width: radius * 2, height: radius * 2)
            .foregroundStyle(.white.opacity(0.42))
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let vector = CGSize(
                            width: value.location.x - radius,
                            height: value.location.y - radius
                        )
                        let length = max(hypot(vector.width, vector.height), 1)
                        let scale = min(1, radius / length)
                        knobOffset = CGSize(width: vector.width * scale, height: vector.height * scale)
                        onChanged(SIMD2(
                            Float(knobOffset.width / radius),
                            Float(knobOffset.height / radius)
                        ))
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.72)) {
                            knobOffset = .zero
                        }
                        onChanged(.zero)
                    }
            )
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint("拖动摇杆控制\(title)")
    }
}

private struct GaussianParticleLoadingView: View {
    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                Canvas { context, size in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    context.blendMode = .plusLighter

                    for index in 0..<56 {
                        let seed = Double(index) * 0.61803398875
                        let angle = seed * .pi * 2 + time * (0.16 + Double(index % 5) * 0.025)
                        let pulse = 0.72 + 0.28 * sin(time * 1.7 + seed * 9)
                        let orbitX = (28 + Double(index % 9) * 5.5) * pulse
                        let orbitY = (16 + Double(index % 7) * 3.8) * pulse
                        let depth = 0.52 + 0.48 * sin(angle * 1.4 + seed * 4)
                        let radius = 1.6 + depth * 3.8
                        let point = CGPoint(
                            x: center.x + cos(angle) * orbitX,
                            y: center.y + sin(angle * 1.13) * orbitY
                        )
                        let color = particleColor(index: index, opacity: 0.22 + depth * 0.55)
                        let rect = CGRect(
                            x: point.x - radius * 1.7,
                            y: point.y - radius,
                            width: radius * 3.4,
                            height: radius * 2
                        )
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .radialGradient(
                                Gradient(colors: [color, color.opacity(0)]),
                                center: point,
                                startRadius: 0,
                                endRadius: radius * 1.7
                            )
                        )
                    }
                }
            }
            .frame(width: 220, height: 138)

            Text("正在聚合高斯粒子")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text("解析位置、尺度、颜色与球谐数据…")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.66))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在解析并载入高斯场景")
    }

    private func particleColor(index: Int, opacity: Double) -> Color {
        switch index % 4 {
        case 0: AppTheme.accent.opacity(opacity)
        case 1: AppTheme.highlight.opacity(opacity)
        case 2: Color.cyan.opacity(opacity)
        default: Color.white.opacity(opacity * 0.82)
        }
    }
}

private struct SplatOverlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(.black.opacity(configuration.isPressed ? 0.72 : 0.48), in: Circle())
    }
}

private struct GaussianMetalView: UIViewRepresentable {
    let fileURL: URL
    let camera: SplatCameraController
    let onLoadStateChanged: (SplatLoadState) -> Void

    func makeCoordinator() -> GaussianMetalRenderer.Coordinator {
        GaussianMetalRenderer.Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        guard let device = MTLCreateSystemDefaultDevice() else {
            onLoadStateChanged(.failed("此设备不支持 Metal。"))
            return view
        }
        view.device = device
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.depthStencilPixelFormat = .depth32Float
        view.sampleCount = 1
        view.clearColor = MTLClearColor(red: 0.015, green: 0.015, blue: 0.02, alpha: 1)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false

        let renderer = GaussianMetalRenderer(
            view: view,
            camera: camera,
            onLoadStateChanged: onLoadStateChanged
        )
        context.coordinator.renderer = renderer
        view.delegate = renderer
        Task { await renderer?.load(fileURL) }
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {}

    static func dismantleUIView(_ view: MTKView, coordinator: GaussianMetalRenderer.Coordinator) {
        view.isPaused = true
        view.delegate = nil
        coordinator.renderer = nil
    }
}

@MainActor
private final class GaussianMetalRenderer: NSObject, MTKViewDelegate {
    final class Coordinator {
        var renderer: GaussianMetalRenderer?
    }

    private weak var view: MTKView?
    private let camera: SplatCameraController
    private let onLoadStateChanged: (SplatLoadState) -> Void
    private let commandQueue: MTLCommandQueue
    private let semaphore = DispatchSemaphore(value: 3)
    private var renderer: SplatRenderer?
    private var drawableSize = CGSize.zero
    private var previousFrameTime = CACurrentMediaTime()

    init?(
        view: MTKView,
        camera: SplatCameraController,
        onLoadStateChanged: @escaping (SplatLoadState) -> Void
    ) {
        guard let device = view.device, let commandQueue = device.makeCommandQueue() else { return nil }
        self.view = view
        self.camera = camera
        self.onLoadStateChanged = onLoadStateChanged
        self.commandQueue = commandQueue
        super.init()
    }

    func load(_ url: URL) async {
        guard let view, let device = view.device else { return }
        onLoadStateChanged(.loading)
        do {
            let renderer = try SplatRenderer(
                device: device,
                colorFormat: view.colorPixelFormat,
                depthFormat: view.depthStencilPixelFormat,
                sampleCount: view.sampleCount,
                maxViewCount: 1,
                maxSimultaneousRenders: 3,
                highQualityDepth: false,
                clearColor: view.clearColor
            )
            let points = try await AutodetectSceneReader(url).readAll()
            let chunk = try SplatChunk(device: device, from: points)
            await renderer.addChunk(chunk)
            self.renderer = renderer
            onLoadStateChanged(.ready)
        } catch {
            renderer = nil
            onLoadStateChanged(.failed(error.localizedDescription))
        }
    }

    func draw(in view: MTKView) {
        guard let renderer, renderer.isReadyToRender,
              drawableSize.width > 0, drawableSize.height > 0,
              let drawable = view.currentDrawable else { return }
        _ = semaphore.wait(timeout: .distantFuture)
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            semaphore.signal()
            return
        }
        let semaphore = semaphore
        commandBuffer.addCompletedHandler { _ in semaphore.signal() }

        let now = CACurrentMediaTime()
        camera.advance(by: Float(now - previousFrameTime))
        previousFrameTime = now
        let projection = splatPerspective(
            verticalFieldOfView: 65 * .pi / 180,
            aspectRatio: Float(drawableSize.width / drawableSize.height),
            nearZ: 0.05,
            farZ: 500
        )
        let viewport = SplatRenderer.ViewportDescriptor(
            viewport: MTLViewport(
                originX: 0,
                originY: 0,
                width: drawableSize.width,
                height: drawableSize.height,
                znear: 0,
                zfar: 1
            ),
            projectionMatrix: projection,
            viewMatrix: camera.viewMatrix,
            screenSize: SIMD2(Int(drawableSize.width), Int(drawableSize.height))
        )

        do {
            let didRender = try renderer.render(
                viewports: [viewport],
                colorTexture: drawable.texture,
                colorStoreAction: .store,
                depthTexture: view.depthStencilTexture,
                rasterizationRateMap: nil,
                renderTargetArrayLength: 0,
                to: commandBuffer
            )
            if didRender { commandBuffer.present(drawable) }
            commandBuffer.commit()
        } catch {
            semaphore.signal()
            onLoadStateChanged(.failed(error.localizedDescription))
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawableSize = size
    }
}

private func splatRotation(radians: Float, axis: SIMD3<Float>) -> simd_float4x4 {
    let unit = normalize(axis)
    let cosine = cos(radians)
    let sine = sin(radians)
    let inverseCosine = 1 - cosine
    let x = unit.x, y = unit.y, z = unit.z
    return simd_float4x4(columns: (
        SIMD4(cosine + x * x * inverseCosine, y * x * inverseCosine + z * sine, z * x * inverseCosine - y * sine, 0),
        SIMD4(x * y * inverseCosine - z * sine, cosine + y * y * inverseCosine, z * y * inverseCosine + x * sine, 0),
        SIMD4(x * z * inverseCosine + y * sine, y * z * inverseCosine - x * sine, cosine + z * z * inverseCosine, 0),
        SIMD4(0, 0, 0, 1)
    ))
}

private func splatTranslation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    simd_float4x4(columns: (
        SIMD4(1, 0, 0, 0),
        SIMD4(0, 1, 0, 0),
        SIMD4(0, 0, 1, 0),
        SIMD4(x, y, z, 1)
    ))
}

private func splatPerspective(
    verticalFieldOfView: Float,
    aspectRatio: Float,
    nearZ: Float,
    farZ: Float
) -> simd_float4x4 {
    let y = 1 / tan(verticalFieldOfView * 0.5)
    let x = y / max(aspectRatio, 0.001)
    let z = farZ / (nearZ - farZ)
    return simd_float4x4(columns: (
        SIMD4(x, 0, 0, 0),
        SIMD4(0, y, 0, 0),
        SIMD4(0, 0, z, -1),
        SIMD4(0, 0, z * nearZ, 0)
    ))
}
