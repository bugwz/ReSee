import SwiftUI

struct SceneLibraryView: View {
    @EnvironmentObject private var repository: SceneRepository
    let startCapture: () -> Void

    var body: some View {
        Group {
            if repository.scenes.isEmpty {
                emptyState
            } else {
                sceneList
            }
        }
        .navigationTitle("回见")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: startCapture) {
                    Label("记录空间", systemImage: "plus")
                }
            }
        }
        .alert(
            "保存出现问题",
            isPresented: Binding(
                get: { repository.lastError != nil },
                set: { _ in }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(repository.lastError ?? "未知错误")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有空间", systemImage: "cube.transparent")
        } description: {
            Text("从一个房间、展位或设备点位开始，缓慢移动手机记录它的结构。")
        } actions: {
            Button(action: startCapture) {
                Label("开始第一次记录", systemImage: "viewfinder")
                    .font(.headline)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)
        }
    }

    private var sceneList: some View {
        List {
            Section {
                ForEach(repository.scenes) { scene in
                    NavigationLink(value: scene) {
                        SceneRow(scene: scene)
                    }
                }
                .onDelete(perform: repository.delete)
            } header: {
                Text("我的空间")
            } footer: {
                Text("向左滑动可删除本地场景索引。")
            }
        }
        .navigationDestination(for: SpatialScene.self) { scene in
            SceneViewerView(scene: scene)
        }
    }
}

private struct SceneRow: View {
    let scene: SpatialScene

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(AppTheme.panel)
                Image(systemName: scene.capture.supportsLiDAR ? "cube.fill" : "camera.fill")
                    .font(.title2)
                    .foregroundStyle(scene.capture.supportsLiDAR ? AppTheme.success : AppTheme.accent)
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 5) {
                Text(scene.name).font(.headline)
                Text(scene.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(scene.capture.meshAnchorCount) 个网格区块 · \(scene.capture.duration.formattedDuration)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

extension TimeInterval {
    var formattedDuration: String {
        let seconds = max(0, Int(self.rounded()))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

