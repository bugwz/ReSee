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
    @State private var isCaptureStarted = false
    @State private var renderingProgress = 0.0
    @State private var renderingMessage = "正在准备生成"
    @State private var generatedScene: SpatialScene?
    @State private var renderingError: String?
    @State private var captureError: String?
    @StateObject private var targetProjection = CaptureTargetProjection()

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
                targetProjection: targetProjection,
                isCaptureEnabled: isCaptureStarted,
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

            CaptureTargetOverlay(
                progress: progress,
                targetProjection: targetProjection,
                isCaptureStarted: isCaptureStarted
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
        .onAppear {
            AppOrientationController.request(.portrait)
        }
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
        Group {
            if isCaptureStarted {
                activeCaptureGuidance
            } else {
                captureReadyPanel
            }
        }
    }

    private var captureReadyPanel: some View {
        VStack(spacing: 14) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 32, weight: .medium))

            VStack(spacing: 5) {
                Text("准备开始拍摄")
                    .font(.headline)
                Text(captureReadinessMessage)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.76))
                    .multilineTextAlignment(.center)
            }

            Button(action: beginCapture) {
                Label("开始拍摄", systemImage: "record.circle")
                    .font(.headline)
                    .foregroundStyle(canBeginCapture ? .black : .white.opacity(0.62))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        canBeginCapture ? Color.white : Color.white.opacity(0.16),
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canBeginCapture)

            Text("点击后才会建立点位并开始自动采集")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.64))
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.15))
        }
        .padding(.bottom, 12)
    }

    private var activeCaptureGuidance: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                SphereCoverageMap(
                    capturedDirectionIDs: progress.capturedDirectionIDs,
                    currentDirectionID: progress.currentDirectionID
                )
                .frame(maxWidth: .infinity)

                CapturePositionMap(
                    viewpointPositions: progress.viewpointPositions,
                    currentPosition: progress.currentPosition,
                    currentYawRadians: progress.currentYawRadians,
                    headingRadians: progress.activeViewpointHeadingRadians
                )
                .frame(maxWidth: .infinity)
            }
            .frame(height: 148)

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

    private var canBeginCapture: Bool {
        progress.trackingQuality == .normal
            && progress.isPortraitCaptureOrientation
    }

    private var captureReadinessMessage: String {
        guard progress.trackingQuality == .normal else {
            return "缓慢移动手机，等待空间定位稳定"
        }
        guard progress.isPortraitCaptureOrientation else {
            return "请先竖直握持手机"
        }
        return "定位已稳定，请保持当前方向作为全景正前方"
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
        isCaptureStarted = false
        flow = .recording
    }

    private func beginCapture() {
        guard canBeginCapture, !isCaptureStarted else { return }
        frames = []
        startedAt = .now
        progress = CaptureProgressState(recordingType: selectedType)
        isCaptureStarted = true
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
                    modelVersion: "equirectangular-v4",
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
        isCaptureStarted = false
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
                        Text("拍摄时请始终竖直握持手机，将橙色目标点移入画面中央。玻璃、镜面、纯色墙和快速晃动会降低记录质量。")
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
                    Button("进入取景", action: start)
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

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "circle.grid.3x3.fill")
                    .frame(width: 12)
                Text("已拍摄点")
                Spacer(minLength: 2)
                Text("\(capturedDirectionIDs.count)/\(CaptureProgressState.targetCount)")
                    .monospacedDigit()
            }
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .frame(height: 14)

            VStack(spacing: 3) {
                ForEach(Array(CaptureDirection.bands.reversed().enumerated()), id: \.offset) { _, band in
                    HStack(spacing: 3) {
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(AppTheme.success)
                        .frame(width: 7, height: 7)
                    Text("已拍摄")
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(AppTheme.highlight)
                        .frame(width: 7, height: 7)
                    Text("未拍摄")
                }
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.72))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 12)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.12))
        }
    }

    private func color(for directionID: Int) -> Color {
        if capturedDirectionIDs.contains(directionID) {
            return AppTheme.success
        }
        if currentDirectionID == directionID {
            return AppTheme.highlight
        }
        return AppTheme.highlight.opacity(0.32)
    }
}

private struct CaptureTargetOverlay: View {
    let progress: CaptureProgressState
    @ObservedObject var targetProjection: CaptureTargetProjection
    let isCaptureStarted: Bool

    private var showsTarget: Bool {
        isCaptureStarted
            && progress.motionPhase == .scanning
            && progress.trackingQuality != .unavailable
            && progress.currentTargetDirection != nil
    }

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(
                x: proxy.size.width / 2,
                y: proxy.size.height * 0.44
            )

            ZStack {
                if showsTarget {
                    targetMarker
                        .position(targetPosition(in: proxy.size, center: center))
                        .animation(
                            .spring(response: 0.46, dampingFraction: 0.84),
                            value: progress.currentDirectionID
                        )
                }

                if isCaptureStarted {
                    Circle()
                        .stroke(
                            progress.isPortraitCaptureOrientation
                                ? .white.opacity(0.92)
                                : Color.red.opacity(0.9),
                            style: StrokeStyle(lineWidth: 3, dash: [5, 4])
                        )
                        .frame(width: 58, height: 58)
                        .background(.black.opacity(0.12), in: Circle())
                        .position(center)
                }

                if isCaptureStarted && !progress.isPortraitCaptureOrientation {
                    Label("请竖直握持手机", systemImage: "iphone.gen3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(.red.opacity(0.82), in: Capsule())
                        .position(x: center.x, y: center.y + 58)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progress.guidance)
    }

    private var targetMarker: some View {
        ZStack {
            Circle()
                .fill(AppTheme.highlight)
                .frame(width: 34, height: 34)
            Circle()
                .stroke(.white, lineWidth: 3)
                .frame(width: 42, height: 42)
            Circle()
                .fill(.white)
                .frame(width: 7, height: 7)
        }
        .shadow(color: .black.opacity(0.4), radius: 5, y: 2)
    }

    private func targetPosition(in size: CGSize, center: CGPoint) -> CGPoint {
        if let projected = targetProjection.position {
            return CGPoint(
                x: min(max(projected.x, 28), size.width - 28),
                y: min(max(projected.y, 90), size.height - 190)
            )
        }
        guard let targetYaw = progress.currentTargetYawRadians,
              let target = progress.currentTargetDirection else { return center }
        let yawDelta = (targetYaw - progress.currentYawRadians).shortestSignedAngle
        let pitchDelta = target.pitchRadians - progress.currentPitchRadians
        let maximumX = max(size.width / 2 - 28, 1)
        let maximumY = max(min(center.y - 90, size.height - center.y - 190), 1)
        let x = CGFloat(yawDelta / (55 * .pi / 180)) * maximumX
        let y = CGFloat(-pitchDelta / (72 * .pi / 180)) * maximumY
        return CGPoint(
            x: center.x + min(max(x, -maximumX), maximumX),
            y: center.y + min(max(y, -maximumY), maximumY)
        )
    }
}

private struct CapturePositionMap: View {
    let viewpointPositions: [Vector3]
    let currentPosition: Vector3
    let currentYawRadians: Float
    let headingRadians: Float

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "location.north.fill")
                    .frame(width: 12)
                Text("俯视位置")
                Spacer(minLength: 2)
                Text("前 ↑")
            }
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .frame(height: 14)

            ZStack {
                Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let origin = viewpointPositions.last ?? .zero
                let allPositions = viewpointPositions + [currentPosition]
                let furthest = allPositions.reduce(Float(1.2)) { result, position in
                    let local = localPosition(of: position, from: origin)
                    return max(result, max(abs(local.x), abs(local.forward)))
                }
                let scale = min(size.width, size.height) * 0.32 / CGFloat(furthest)

                var grid = Path()
                grid.move(to: CGPoint(x: center.x, y: 12))
                grid.addLine(to: CGPoint(x: center.x, y: size.height - 12))
                grid.move(to: CGPoint(x: 12, y: center.y))
                grid.addLine(to: CGPoint(x: size.width - 12, y: center.y))
                context.stroke(grid, with: .color(.white.opacity(0.16)), lineWidth: 1)

                func point(for position: Vector3) -> CGPoint {
                    let local = localPosition(of: position, from: origin)
                    return CGPoint(
                        x: center.x + CGFloat(local.x) * scale,
                        y: center.y - CGFloat(local.forward) * scale
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
                let relativeYaw = currentYawRadians - headingRadians
                let forward = CGVector(
                    dx: CGFloat(sin(relativeYaw)),
                    dy: CGFloat(-cos(relativeYaw))
                )
                let right = CGVector(dx: -forward.dy, dy: forward.dx)
                var deviceArrow = Path()
                deviceArrow.move(to: CGPoint(
                    x: deviceLocation.x + forward.dx * 8,
                    y: deviceLocation.y + forward.dy * 8
                ))
                deviceArrow.addLine(to: CGPoint(
                    x: deviceLocation.x - forward.dx * 5 + right.dx * 5,
                    y: deviceLocation.y - forward.dy * 5 + right.dy * 5
                ))
                deviceArrow.addLine(to: CGPoint(
                    x: deviceLocation.x - forward.dx * 5 - right.dx * 5,
                    y: deviceLocation.y - forward.dy * 5 - right.dy * 5
                ))
                deviceArrow.closeSubpath()
                context.fill(deviceArrow, with: .color(.yellow))
            }

                Text("前").frame(maxHeight: .infinity, alignment: .top)
                Text("后").frame(maxHeight: .infinity, alignment: .bottom)
                Text("左").frame(maxWidth: .infinity, alignment: .leading)
                Text("右").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white.opacity(0.66))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 4) {
                Image(systemName: "location.north.fill")
                    .foregroundStyle(.yellow)
                    .frame(width: 10)
                Text("手机")
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.72))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 12)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.12))
        }
    }

    private func localPosition(
        of position: Vector3,
        from origin: Vector3
    ) -> (x: Float, forward: Float) {
        let deltaX = position.x - origin.x
        let deltaZ = position.z - origin.z
        return (
            x: deltaX * cos(headingRadians) - deltaZ * sin(headingRadians),
            forward: deltaX * sin(headingRadians) + deltaZ * cos(headingRadians)
        )
    }
}
