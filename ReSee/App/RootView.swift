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
        .background(AppTheme.background.ignoresSafeArea())
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
                    .foregroundStyle(AppTheme.highlight)

                Text("再次走进，曾经在场的空间。")
                    .font(.largeTitle.bold())

                Text("回见使用 ARKit 引导你覆盖空间方向，并在本地生成可以缩放、切换视角与固定点的浏览记录。连续自由移动的高精空间模型仍在开发中。")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    InfoRow(icon: "arrow.triangle.2.circlepath", title: "全景浏览", detail: "自由环视、缩放画面与切换多个固定点")
                    InfoRow(icon: "circle.dotted", title: "覆盖引导", detail: "显示当前位置、已记录方向和遗漏区域")
                    InfoRow(icon: "lock.shield", title: "本地优先", detail: "场景索引和生成画面保存在设备本地")
                }
            }
            .padding(24)
        }
        .background(AppTheme.groupedBackground)
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
        .background(AppTheme.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(AppTheme.border)
        }
    }
}
