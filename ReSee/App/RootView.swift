import SwiftUI

struct RootView: View {
    @State private var selectedTab: AppTab = .library
    @State private var isPresentingCapture = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                SceneLibraryView {
                    isPresentingCapture = true
                }
            }
            .tag(AppTab.library)
            .tabItem {
                Label("空间", systemImage: "square.stack.3d.up.fill")
            }

            NavigationStack {
                AboutView()
            }
            .tag(AppTab.about)
            .tabItem {
                Label("关于", systemImage: "info.circle.fill")
            }
        }
        .tint(AppTheme.accent)
        .fullScreenCover(isPresented: $isPresentingCapture) {
            CaptureView()
        }
    }
}

private enum AppTab {
    case library
    case about
}

private struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Image(systemName: "viewfinder.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(AppTheme.accent)

                Text("再次走进，曾经在场的空间。")
                    .font(.largeTitle.bold())

                Text("回见使用 ARKit 记录设备运动、深度和空间结构，为每个房间、展位或设备点位建立可以回看的数字空间。")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    InfoRow(icon: "move.3d", title: "自由浏览", detail: "在已采集范围内移动、旋转与缩放")
                    InfoRow(icon: "mappin.and.ellipse", title: "空间标注", detail: "将资料绑定到模型表面，而不是一张照片")
                    InfoRow(icon: "lock.shield", title: "本地优先", detail: "首版场景索引保存在设备本地")
                }
            }
            .padding(24)
        }
        .navigationTitle("关于回见")
    }
}

private struct InfoRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

