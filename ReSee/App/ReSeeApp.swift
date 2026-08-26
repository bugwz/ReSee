import SwiftUI

@main
struct ReSeeApp: App {
    @StateObject private var sceneRepository = SceneRepository()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sceneRepository)
                .preferredColorScheme(.dark)
        }
    }
}

