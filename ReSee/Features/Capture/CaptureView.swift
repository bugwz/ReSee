import ARKit
import SwiftUI

struct CaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var repository: SceneRepository

    @State private var sceneName = ""
    @State private var metrics = CaptureMetrics()
    @State private var startedAt = Date()
    @State private var isNamingScene = false

    private var canSave: Bool {
        metrics.trackingQuality != .unavailable
    }

    var body: some View {
        ZStack {
            ARCaptureView(metrics: $metrics)
                .ignoresSafeArea()

            LinearGradient(
                colors: [.black.opacity(0.72), .clear, .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                guidancePanel
                captureControls
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .statusBarHidden()
        .onAppear { startedAt = .now }
        .alert("保存这个空间", isPresented: $isNamingScene) {
            TextField("例如：工作室东侧", text: $sceneName)
            Button("取消", role: .cancel) {}
            Button("保存") { saveScene() }
        } message: {
            Text("名字可以帮助你之后快速找到这次记录。")
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 42, height: 42)
                    .background(.ultraThinMaterial, in: Circle())
            }

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(metrics.trackingQuality == .normal ? AppTheme.success : AppTheme.accent)
                    .frame(width: 8, height: 8)
                Text(metrics.trackingQuality.title)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .foregroundStyle(.white)
    }

    private var guidancePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(metrics.guidance, systemImage: "figure.walk.motion")
                    .font(.headline)
                Spacer()
                Text("\(Int(metrics.coverage * 100))%")
                    .font(.headline.monospacedDigit())
            }

            ProgressView(value: metrics.coverage)
                .tint(AppTheme.accent)

            HStack(spacing: 18) {
                Label("\(metrics.meshAnchorCount) 网格", systemImage: "square.3.layers.3d")
                Label(metrics.supportsLiDAR ? "LiDAR" : "视觉定位", systemImage: "sensor.tag.radiowaves.forward")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.bottom, 18)
    }

    private var captureControls: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("正在记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TimelineView(.periodic(from: startedAt, by: 1)) { context in
                    Text(context.date.timeIntervalSince(startedAt).formattedDuration)
                        .font(.title3.monospacedDigit().bold())
                }
            }

            Spacer()

            Button {
                isNamingScene = true
            } label: {
                Label("完成", systemImage: "checkmark")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
            .disabled(!canSave)
        }
        .foregroundStyle(.white)
        .padding(.bottom, 8)
    }

    private func saveScene() {
        repository.add(
            name: sceneName,
            summary: CaptureSummary(
                duration: Date.now.timeIntervalSince(startedAt),
                meshAnchorCount: metrics.meshAnchorCount,
                supportsLiDAR: metrics.supportsLiDAR,
                trackingQuality: metrics.trackingQuality
            )
        )
        dismiss()
    }
}

struct CaptureMetrics: Equatable {
    var trackingQuality: TrackingQuality = .unavailable
    var meshAnchorCount = 0
    var supportsLiDAR = ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)

    var coverage: Double {
        guard supportsLiDAR else {
            return trackingQuality == .normal ? 0.25 : 0.05
        }
        return min(Double(meshAnchorCount) / 28, 1)
    }

    var guidance: String {
        switch trackingQuality {
        case .unavailable: "缓慢移动手机以开始定位"
        case .limited: "对准有纹理的物体，避免快速晃动"
        case .normal where coverage < 0.35: "沿空间边缘缓慢前进"
        case .normal where coverage < 0.8: "补拍家具背面和角落"
        case .normal: "覆盖良好，可以完成记录"
        }
    }
}

