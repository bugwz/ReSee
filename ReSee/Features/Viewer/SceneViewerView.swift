import SwiftUI

struct SceneViewerView: View {
    let scene: SpatialScene

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                modelPlaceholder
                summaryGrid
                annotationSection
            }
            .padding(18)
        }
        .navigationTitle(scene.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var modelPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.15, blue: 0.19), Color(red: 0.2, green: 0.12, blue: 0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 14) {
                Image(systemName: "cube.transparent.fill")
                    .font(.system(size: 58))
                    .foregroundStyle(AppTheme.accent)
                Text("空间预览待生成")
                    .font(.title2.bold())
                Text("当前已保存采集统计；下一阶段将接入网格文件持久化与 RealityKit 浏览。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    private var summaryGrid: some View {
        HStack(spacing: 12) {
            MetricCard(value: scene.capture.duration.formattedDuration, label: "采集时长")
            MetricCard(value: "\(scene.capture.meshAnchorCount)", label: "网格区块")
            MetricCard(value: scene.capture.supportsLiDAR ? "是" : "否", label: "LiDAR")
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
                Label("生成可浏览网格后，即可把信息钉在物体表面。", systemImage: "mappin.slash")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }
}

private struct MetricCard: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(AppTheme.panel, in: RoundedRectangle(cornerRadius: 16))
    }
}

