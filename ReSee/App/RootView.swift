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
                ExternalAssetLibraryView()
            }
            .tag(AppTab.externalAssets)
            .tabItem {
                Label("外部", systemImage: "square.and.arrow.down")
            }

            NavigationStack {
                SettingsView()
            }
            .tag(AppTab.settings)
            .tabItem {
                Label("设置", systemImage: "gearshape.fill")
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
    case externalAssets
    case settings
}
