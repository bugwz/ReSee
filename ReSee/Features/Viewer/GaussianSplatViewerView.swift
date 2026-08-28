import Metal
import MetalKit
import MetalSplatter
import simd
import SplatIO
import SwiftUI

struct GaussianSplatViewerView: View {
    @EnvironmentObject private var settings: AppSettings
    let fileURL: URL

    @StateObject private var camera = SplatCameraController()
    @State private var loadState: SplatLoadState = .loading
    @State private var controlsVisible = true
    @State private var hasAppliedVisibilityPreference = false

    var body: some View {
        ZStack {
            Color.black
            GaussianMetalView(fileURL: fileURL, camera: camera) { state in
                loadState = state
            }

            controlOverlay

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
                controlSettingsMenu
            }
            .buttonStyle(SplatOverlayButtonStyle())
            .padding(12)
        }
        .onAppear {
            camera.setMovementSpeedMultiplier(settings.splatMovementSpeed.multiplier)
            guard !hasAppliedVisibilityPreference else { return }
            controlsVisible = settings.showsSplatControlsByDefault
            hasAppliedVisibilityPreference = true
        }
        .onChange(of: settings.splatMovementSpeed) { _, speed in
            camera.setMovementSpeedMultiplier(speed.multiplier)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Gaussian Splatting 自由空间查看器")
    }

    private var controlOverlay: some View {
        GeometryReader { geometry in
            let horizontalInset = max(geometry.safeAreaInsets.leading, 18)
            let bottomInset = max(geometry.safeAreaInsets.bottom, 16)
            let availableDiameter = max((geometry.size.width - horizontalInset * 2 - 28) / 2, 96)
            let diameter = min(settings.splatJoystickSize.diameter, availableDiameter)

            VStack {
                if settings.showsSplatSceneInfo {
                    HStack {
                        Label("6DoF", systemImage: "move.3d")
                        Spacer()
                        Text("MetalSplatter")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.leading, horizontalInset)
                    .padding(.top, max(geometry.safeAreaInsets.top, 12))
                    .padding(.trailing, 156)
                }
                Spacer()
                if controlsVisible {
                    HStack(alignment: .bottom) {
                        joystick(for: leadingControl, diameter: diameter)
                        Spacer(minLength: 28)
                        joystick(for: trailingControl, diameter: diameter)
                    }
                    .padding(.horizontal, horizontalInset)
                    .padding(.bottom, bottomInset)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controlsVisible)
    }

    private var leadingControl: SplatControl {
        settings.splatControlLayout == .movementOnLeft ? .movement : .look
    }

    private var trailingControl: SplatControl {
        settings.splatControlLayout == .movementOnLeft ? .look : .movement
    }

    private func joystick(for control: SplatControl, diameter: CGFloat) -> some View {
        SplatJoystick(
            title: control.accessibilityTitle,
            systemImage: control.systemImage,
            diameter: diameter,
            showsGuides: settings.showsSplatJoystickGuides,
            onChanged: control == .movement ? camera.setMovement : camera.setLook
        )
    }

    private var controlSettingsMenu: some View {
        Menu {
            Button {
                settings.splatControlLayout = settings.splatControlLayout == .movementOnLeft
                    ? .movementOnRight
                    : .movementOnLeft
            } label: {
                Label("左右互换", systemImage: "arrow.left.arrow.right")
            }

            Picker("移动速度", selection: $settings.splatMovementSpeed) {
                ForEach(SplatMovementSpeed.allCases) { speed in
                    Text(speed.title).tag(speed)
                }
            }

            Picker("圆盘大小", selection: $settings.splatJoystickSize) {
                ForEach(SplatJoystickSize.allCases) { size in
                    Text(size.title).tag(size)
                }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
        }
        .accessibilityLabel("控制器设置")
    }

    @ViewBuilder
    private var statusOverlay: some View {
        switch loadState {
        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                    .tint(.white)
                Text("正在解析高斯场景")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
        case let .revealing(loaded, total):
            VStack {
                HStack(spacing: 8) {
                    ProgressView(value: Double(loaded), total: Double(max(total, 1)))
                        .tint(.white)
                        .frame(width: 92)
                    Text("真实粒子显影 \(loaded.formatted()) / \(total.formatted())")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.black.opacity(0.62), in: Capsule())
                Spacer()
            }
            .padding(.top, 14)
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

private enum SplatControl: Equatable {
    case movement
    case look

    var accessibilityTitle: String {
        switch self {
        case .movement: "移动"
        case .look: "视角"
        }
    }

    var systemImage: String {
        switch self {
        case .movement: "move.3d"
        case .look: "scope"
        }
    }
}

private enum SplatLoadState: Equatable {
    case loading
    case revealing(loaded: Int, total: Int)
    case ready
    case failed(String)
}

enum SplatJoystickMapping {
    static func movement(_ screenVector: SIMD2<Float>) -> SIMD2<Float> {
        screenVector
    }

    static func look(_ screenVector: SIMD2<Float>) -> SIMD2<Float> {
        screenVector
    }
}

@MainActor
final class SplatCameraController: ObservableObject {
    private(set) var position = SIMD3<Float>(0, 0, 8)
    private(set) var yaw: Float = 0
    private(set) var pitch: Float = 0
    private(set) var nearZ: Float = 0.01
    private(set) var farZ: Float = 500
    private(set) var movement = SIMD2<Float>.zero
    private(set) var look = SIMD2<Float>.zero
    private var initialPosition = SIMD3<Float>(0, 0, 8)
    private var movementSpeed: Float = 2.2
    private var movementSpeedMultiplier: Float = 1

    func setMovement(_ value: SIMD2<Float>) {
        movement = SplatJoystickMapping.movement(value)
    }

    func setLook(_ value: SIMD2<Float>) {
        look = SplatJoystickMapping.look(value)
    }

    func setMovementSpeedMultiplier(_ multiplier: Float) {
        movementSpeedMultiplier = multiplier
    }

    func frame(_ framing: SplatSceneFraming) {
        initialPosition = framing.center + SIMD3<Float>(0, 0, framing.cameraDistance)
        movementSpeed = framing.movementSpeed
        nearZ = framing.nearZ
        farZ = framing.farZ
        reset()
    }

    func reset() {
        position = initialPosition
        yaw = 0
        pitch = 0
        movement = .zero
        look = .zero
    }

    func advance(by elapsed: Float) {
        let frameTime = min(max(elapsed, 0), 0.05)
        // The phone is the observer's window: right means turn right and an
        // upward screen vector means lift the observer's gaze.
        yaw -= look.x * frameTime * 1.35
        pitch = min(max(pitch - look.y * frameTime * 1.2, -.pi * 0.48), .pi * 0.48)

        position += (
            horizontalRight * movement.x
                + horizontalForward * -movement.y
        ) * movementSpeed * movementSpeedMultiplier * frameTime
    }

    var horizontalForward: SIMD3<Float> {
        SIMD3<Float>(-sin(yaw), 0, -cos(yaw))
    }

    var horizontalRight: SIMD3<Float> {
        SIMD3<Float>(cos(yaw), 0, -sin(yaw))
    }

    var viewingDirection: SIMD3<Float> {
        let horizontal = cos(pitch)
        return SIMD3<Float>(
            -sin(yaw) * horizontal,
            sin(pitch),
            -cos(yaw) * horizontal
        )
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

struct SplatSceneFraming: Equatable {
    let center: SIMD3<Float>
    let radius: Float
    let cameraDistance: Float
    let movementSpeed: Float
    let nearZ: Float
    let farZ: Float

    static func fitted(to positions: [SIMD3<Float>]) -> SplatSceneFraming {
        let finitePositions = positions.filter {
            $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
        }
        guard !finitePositions.isEmpty else {
            return SplatSceneFraming(
                center: .zero,
                radius: 4,
                cameraDistance: 8,
                movementSpeed: 2.2,
                nearZ: 0.01,
                farZ: 500
            )
        }

        let maximumSampleCount = 20_000
        let stride = max(finitePositions.count / maximumSampleCount, 1)
        let sample = Swift.stride(from: 0, to: finitePositions.count, by: stride).map {
            calibratedPosition(finitePositions[$0])
        }
        let xRange = percentileRange(sample.map(\.x))
        let yRange = percentileRange(sample.map(\.y))
        let zRange = percentileRange(sample.map(\.z))
        let lower = SIMD3<Float>(xRange.lowerBound, yRange.lowerBound, zRange.lowerBound)
        let upper = SIMD3<Float>(xRange.upperBound, yRange.upperBound, zRange.upperBound)
        let center = (lower + upper) * 0.5
        let halfExtent = (upper - lower) * 0.5
        let radius = max(simd_length(halfExtent), 0.1)
        let cameraDistance = max(radius * 1.9, 0.5)

        return SplatSceneFraming(
            center: center,
            radius: radius,
            cameraDistance: cameraDistance,
            movementSpeed: max(radius * 0.45, 0.15),
            nearZ: max(radius * 0.001, 0.005),
            farZ: max(cameraDistance + radius * 8, 100)
        )
    }

    static func calibratedPosition(_ position: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(-position.x, -position.y, position.z)
    }

    private static func percentileRange(_ values: [Float]) -> ClosedRange<Float> {
        let sorted = values.sorted()
        guard sorted.count >= 20 else { return sorted[0]...sorted[sorted.count - 1] }
        let lowerIndex = Int(Float(sorted.count - 1) * 0.01)
        let upperIndex = Int(Float(sorted.count - 1) * 0.99)
        return sorted[lowerIndex]...sorted[upperIndex]
    }
}

private struct SplatJoystick: View {
    let title: String
    let systemImage: String
    let diameter: CGFloat
    let showsGuides: Bool
    let onChanged: (SIMD2<Float>) -> Void

    @State private var knobOffset = CGSize.zero

    private var radius: CGFloat { diameter / 2 }

    var body: some View {
        ZStack {
            Circle()
                .fill(.black.opacity(0.46))
                .overlay { Circle().stroke(.white.opacity(0.3), lineWidth: 1) }
            if showsGuides {
                Image(systemName: "chevron.up")
                    .offset(y: -radius + 15)
                Image(systemName: "chevron.down")
                    .offset(y: radius - 15)
                Image(systemName: "chevron.left")
                    .offset(x: -radius + 15)
                Image(systemName: "chevron.right")
                    .offset(x: radius - 15)
            }
            Circle()
                .fill(.white.opacity(0.82))
                .frame(width: diameter * 0.38, height: diameter * 0.38)
                .overlay { Image(systemName: systemImage).foregroundStyle(.black.opacity(0.72)) }
                .offset(knobOffset)
        }
        .frame(width: diameter, height: diameter)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint("拖动摇杆控制\(title)")
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
        context.coordinator.loadTask = Task { await renderer?.load(fileURL) }
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {}

    static func dismantleUIView(_ view: MTKView, coordinator: GaussianMetalRenderer.Coordinator) {
        view.isPaused = true
        view.delegate = nil
        coordinator.loadTask?.cancel()
        coordinator.loadTask = nil
        coordinator.renderer = nil
    }
}

@MainActor
private final class GaussianMetalRenderer: NSObject, MTKViewDelegate {
    final class Coordinator {
        var renderer: GaussianMetalRenderer?
        var loadTask: Task<Void, Never>?
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
                highQualityDepth: true,
                clearColor: view.clearColor
            )
            let points = try await AutodetectSceneReader(url).readAll()
            guard !points.isEmpty else {
                throw SplatViewerError.emptyScene
            }
            camera.frame(SplatSceneFraming.fitted(to: points.map(\.position)))

            let revealBatchSize = max(10_000, (points.count + 89) / 90)
            var loadedCount = 0
            while loadedCount < points.count {
                try Task.checkCancellation()
                let endIndex = min(loadedCount + revealBatchSize, points.count)
                let chunk = try SplatChunk(
                    device: device,
                    from: Array(points[loadedCount..<endIndex])
                )
                await renderer.addChunk(chunk)
                loadedCount = endIndex
                self.renderer = renderer
                onLoadStateChanged(.revealing(loaded: loadedCount, total: points.count))
                try await Task.sleep(for: .milliseconds(16))
            }
            onLoadStateChanged(.ready)
        } catch is CancellationError {
            renderer = nil
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
            nearZ: camera.nearZ,
            farZ: camera.farZ
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

private enum SplatViewerError: LocalizedError {
    case emptyScene

    var errorDescription: String? {
        "高斯文件中没有可显示的粒子。"
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
