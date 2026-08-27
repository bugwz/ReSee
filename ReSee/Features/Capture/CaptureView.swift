import SwiftUI

struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repository: SceneRepository

    @State private var flow: CaptureFlow = .selection
    @State private var selectedType: RecordingType = .stationary
    @State private var sceneName = ""
    @State private var progress = CaptureProgressState(recordingType: .stationary)
    @State private var frames: [CapturedFramePayload] = []
    @State private var startedAt = Date()
    @State private var renderingProgress = 0.0
    @State private var renderingMessage = "正在准备生成"
    @State private var generatedScene: SpatialScene?
    @State private var renderingError: String?
    @State private var captureError: String?

    private let renderingService = SceneRenderingService()

    var body: some View {
        Group {
            switch flow {
            case .selection:
                RecordingTypeSelectionView(
                    selectedType: $selectedType,
                    sceneName: $sceneName,
                    cancel: { dismiss() },
                    start: startRecording
                )
            case .recording:
                recordingView
            case .rendering:
                renderingView
            case .result:
                resultView
            }
        }
        .animation(.easeInOut(duration: 0.28), value: flow)
        .alert("生成失败", isPresented: Binding(
            get: { renderingError != nil },
            set: { if !$0 { renderingError = nil } }
        )) {
            Button("重新记录") { resetToSelection() }
            Button("退出", role: .cancel) { dismiss() }
        } message: {
            Text(renderingError ?? "未知错误")
        }
    }

    private var recordingView: some View {
        ZStack {
            ARCaptureView(
                recordingType: selectedType,
                progress: $progress,
                onFrameCaptured: { frames.append($0) },
                onCompleted: finishRecording,
                onError: { captureError = $0 }
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.74), .clear, .black.opacity(0.82)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                captureTopBar
                Spacer()
                captureGuidance
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .statusBarHidden()
        .alert("记录无法继续", isPresented: Binding(
            get: { captureError != nil },
            set: { if !$0 { captureError = nil } }
        )) {
            Button("返回选择") { resetToSelection() }
            Button("退出", role: .cancel) { dismiss() }
        } message: {
            Text(captureError ?? "未知错误")
        }
    }

    private var captureTopBar: some View {
        HStack {
            Button { resetToSelection() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.42), in: Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedType.title)
                    .font(.headline)
                Text(progress.pointTitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.leading, 6)

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(progress.trackingQuality == .normal ? AppTheme.success : AppTheme.highlight)
                    .frame(width: 8, height: 8)
                Text(progress.trackingQuality.title)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.black.opacity(0.42), in: Capsule())
        }
        .foregroundStyle(.white)
    }

    private var captureGuidance: some View {
        VStack(spacing: 16) {
            HStack(spacing: 24) {
                SphereCoverageMap(
                    capturedDirectionIDs: progress.capturedDirectionIDs,
                    currentDirectionID: progress.currentDirectionID,
                    isMoving: progress.motionPhase == .movingToNextPoint
                )
                .frame(width: 124, height: 124)

                CapturePositionMap(
                    viewpointPositions: progress.viewpointPositions,
                    currentPosition: progress.currentPosition
                )
                .frame(width: 124, height: 124)
            }

            VStack(spacing: 10) {
                Text(progress.guidance)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                ProgressView(value: progress.overallCoverage)
                    .tint(.white)

                HStack {
                    Label("\(Int(progress.overallCoverage * 100))%", systemImage: "circle.dotted")
                    Spacer()
                    Label(
                        String(format: "x %.1f · z %.1f m", progress.currentPosition.x, progress.currentPosition.z),
                        systemImage: "location.fill"
                    )
                    Spacer()
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Label(
                            context.date.timeIntervalSince(startedAt).formattedDuration,
                            systemImage: "timer"
                        )
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.72))
            }
            .padding(16)
            .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.15))
            }

            Text("覆盖完整后会自动结束记录")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .padding(.bottom, 12)
    }

    private var renderingView: some View {
        ZStack {
            AppTheme.groupedBackground.ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .stroke(AppTheme.border, lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: max(renderingProgress, 0.03))
                        .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: selectedType.systemImage)
                        .font(.system(size: 42))
                        .foregroundStyle(AppTheme.accent)
                }
                .frame(width: 132, height: 132)

                VStack(spacing: 10) {
                    Text("正在渲染生成")
                        .font(.largeTitle.bold())
                    Text(renderingMessage)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("请保持应用开启，原始画面正在合成为 360° 全景。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Text("\(Int(renderingProgress * 100))%")
                    .font(.title2.monospacedDigit().bold())
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(30)
        }
    }

    @ViewBuilder
    private var resultView: some View {
        if let generatedScene {
            NavigationStack {
                SceneViewerView(scene: generatedScene)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("完成") { dismiss() }
                        }
                    }
            }
        } else {
            ProgressView()
        }
    }

    private func startRecording() {
        guard selectedType.isAvailable else { return }
        frames = []
        progress = CaptureProgressState(recordingType: selectedType)
        startedAt = .now
        flow = .recording
    }

    private func finishRecording() {
        guard flow == .recording else { return }
        flow = .rendering
        renderingProgress = 0
        renderingMessage = "正在准备生成"

        let sceneID = UUID()
        let capturedFrames = frames
        let duration = Date.now.timeIntervalSince(startedAt)
        let finalProgress = progress

        Task {
            do {
                let rendered = try await renderingService.render(
                    sceneID: sceneID,
                    recordingType: selectedType,
                    frames: capturedFrames
                ) { value, message in
                    renderingProgress = value
                    renderingMessage = message
                }

                let trimmedName = sceneName.trimmingCharacters(in: .whitespacesAndNewlines)
                let scene = SpatialScene(
                    id: sceneID,
                    name: trimmedName.isEmpty ? "\(selectedType.title) \(repository.scenes.count + 1)" : trimmedName,
                    capture: CaptureSummary(
                        duration: duration,
                        meshAnchorCount: finalProgress.meshAnchorCount,
                        supportsLiDAR: finalProgress.supportsLiDAR,
                        trackingQuality: finalProgress.trackingQuality,
                        capturedFrameCount: rendered.frameCount,
                        viewpointCount: rendered.viewpoints.count,
                        coverage: 1
                    ),
                    recordingType: selectedType,
                    modelVersion: "equirectangular-v3",
                    renderedScene: rendered
                )
                do {
                    try repository.add(scene)
                } catch {
                    try? await renderingService.discard(sceneID: sceneID)
                    throw error
                }
                generatedScene = scene
                flow = .result
            } catch {
                renderingError = error.localizedDescription
            }
        }
    }

    private func resetToSelection() {
        flow = .selection
        frames = []
        generatedScene = nil
        renderingError = nil
        captureError = nil
    }
}

private enum CaptureFlow: Equatable {
    case selection
    case recording
    case rendering
    case result
}

private struct RecordingTypeSelectionView: View {
    @Binding var selectedType: RecordingType
    @Binding var sceneName: String
    let cancel: () -> Void
    let start: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("选择记录方式")
                            .font(.largeTitle.bold())
                        Text("不同方式决定记录范围和最终浏览体验。")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }

                    TextField("为空间命名，例如：工作室东侧", text: $sceneName)
                        .textFieldStyle(.plain)
                        .padding(16)
                        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16).stroke(AppTheme.border)
                        }

                    VStack(spacing: 14) {
                        ForEach(RecordingType.allCases) { type in
                            RecordingTypeCard(
                                type: type,
                                isSelected: selectedType == type,
                                select: { if type.isAvailable { selectedType = type } }
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("记录提示", systemImage: "lightbulb.fill")
                            .font(.headline)
                            .foregroundStyle(AppTheme.highlight)
                        Text("请在光线充足的环境中缓慢转动。玻璃、镜面、纯色墙和快速晃动会降低记录质量。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 18))
                }
                .padding(20)
            }
            .background(AppTheme.groupedBackground)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消", action: cancel)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("开始记录", action: start)
                        .fontWeight(.semibold)
                        .disabled(!selectedType.isAvailable)
                }
            }
        }
    }
}

private struct RecordingTypeCard: View {
    let type: RecordingType
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 16) {
                Image(systemName: type.systemImage)
                    .font(.system(size: 28))
                    .foregroundStyle(type.isAvailable ? AppTheme.accent : .secondary)
                    .frame(width: 52, height: 52)
                    .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 15))

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(type.title).font(.headline)
                        if !type.isAvailable {
                            Text("高级 · 敬请期待")
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppTheme.panel, in: Capsule())
                        }
                    }
                    Text(type.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                    Label(type.estimatedTime, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if type.isAvailable {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? AppTheme.accent : .secondary)
                }
            }
            .padding(16)
            .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected && type.isAvailable ? AppTheme.accent : AppTheme.border, lineWidth: isSelected ? 2 : 1)
            }
            .opacity(type.isAvailable ? 1 : 0.68)
        }
        .buttonStyle(.plain)
        .disabled(!type.isAvailable)
    }
}

private struct SphereCoverageMap: View {
    let capturedDirectionIDs: Set<Int>
    let currentDirectionID: Int?
    let isMoving: Bool

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(CaptureDirection.bands.reversed().enumerated()), id: \.offset) { _, band in
                HStack(spacing: 4) {
                    ForEach(band) { direction in
                        Circle()
                            .fill(color(for: direction.id))
                            .frame(
                                width: currentDirectionID == direction.id ? 9 : 6,
                                height: currentDirectionID == direction.id ? 9 : 6
                            )
                    }
                }
            }

            Image(systemName: isMoving ? "figure.walk" : "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 20))
                .foregroundStyle(.white)
        }
        .padding(10)
        .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 16))
    }

    private func color(for directionID: Int) -> Color {
        if capturedDirectionIDs.contains(directionID) {
            return AppTheme.success
        }
        if currentDirectionID == directionID {
            return AppTheme.highlight
        }
        return .white.opacity(0.28)
    }
}

private struct CapturePositionMap: View {
    let viewpointPositions: [Vector3]
    let currentPosition: Vector3

    var body: some View {
        VStack(spacing: 5) {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let origin = viewpointPositions.first ?? .zero
                let allPositions = viewpointPositions + [currentPosition]
                let furthest = allPositions.reduce(Float(1.2)) { result, position in
                    max(result, max(abs(position.x - origin.x), abs(position.z - origin.z)))
                }
                let scale = min(size.width, size.height) * 0.38 / CGFloat(furthest)

                var grid = Path()
                grid.move(to: CGPoint(x: center.x, y: 4))
                grid.addLine(to: CGPoint(x: center.x, y: size.height - 4))
                grid.move(to: CGPoint(x: 4, y: center.y))
                grid.addLine(to: CGPoint(x: size.width - 4, y: center.y))
                context.stroke(grid, with: .color(.white.opacity(0.16)), lineWidth: 1)

                func point(for position: Vector3) -> CGPoint {
                    CGPoint(
                        x: center.x + CGFloat(position.x - origin.x) * scale,
                        y: center.y + CGFloat(position.z - origin.z) * scale
                    )
                }

                if viewpointPositions.count > 1 {
                    var route = Path()
                    route.move(to: point(for: viewpointPositions[0]))
                    for position in viewpointPositions.dropFirst() {
                        route.addLine(to: point(for: position))
                    }
                    context.stroke(
                        route,
                        with: .color(.white.opacity(0.55)),
                        style: StrokeStyle(lineWidth: 2, dash: [4, 3])
                    )
                }

                for (index, position) in viewpointPositions.enumerated() {
                    let location = point(for: position)
                    let rect = CGRect(x: location.x - 7, y: location.y - 7, width: 14, height: 14)
                    context.fill(Path(ellipseIn: rect), with: .color(AppTheme.success))
                    context.draw(
                        Text("\(index + 1)").font(.system(size: 8, weight: .bold)).foregroundStyle(.white),
                        at: location
                    )
                }

                let deviceLocation = point(for: currentPosition)
                let deviceRect = CGRect(
                    x: deviceLocation.x - 5,
                    y: deviceLocation.y - 5,
                    width: 10,
                    height: 10
                )
                context.fill(Path(ellipseIn: deviceRect), with: .color(AppTheme.highlight))
            }
            .padding(6)
            .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 16))

            Text("俯视位置")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}
