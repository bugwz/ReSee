import SwiftUI
import UIKit

final class ReSeeAppDelegate: NSObject, UIApplicationDelegate {
    static var supportedOrientations: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.supportedOrientations
    }
}

@MainActor
enum AppOrientationController {
    static func request(_ orientations: UIInterfaceOrientationMask) {
        ReSeeAppDelegate.supportedOrientations = orientations
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else { return }

        windowScene.keyWindow?.rootViewController?
            .setNeedsUpdateOfSupportedInterfaceOrientations()
        windowScene.requestGeometryUpdate(
            .iOS(interfaceOrientations: orientations)
        ) { _ in }
    }
}

@main
struct ReSeeApp: App {
    @UIApplicationDelegateAdaptor(ReSeeAppDelegate.self) private var appDelegate
    @StateObject private var sceneRepository = SceneRepository()
    @State private var isShowingLaunchScreen = true
    @State private var isLeavingLaunchScreen = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environmentObject(sceneRepository)
                    .opacity(isShowingLaunchScreen && !isLeavingLaunchScreen ? 0 : 1)
                    .scaleEffect(isShowingLaunchScreen && !isLeavingLaunchScreen ? 1.01 : 1)
                    .allowsHitTesting(!isShowingLaunchScreen)

                if isShowingLaunchScreen {
                    AnimatedLaunchView(isExiting: isLeavingLaunchScreen)
                        .zIndex(1)
                }
            }
            .background(AppTheme.launchBackground.ignoresSafeArea())
            .preferredColorScheme(.light)
            .task {
                guard isShowingLaunchScreen else { return }
                try? await Task.sleep(nanoseconds: 2_150_000_000)
                withAnimation(.easeInOut(duration: 0.85)) {
                    isLeavingLaunchScreen = true
                }
                try? await Task.sleep(nanoseconds: 850_000_000)
                isShowingLaunchScreen = false
            }
        }
    }
}

private struct AnimatedLaunchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isExiting: Bool
    @State private var isAssembled = false
    @State private var isFloating = false

    var body: some View {
        ZStack {
            AppTheme.launchBackground
                .ignoresSafeArea()

            ZStack {
                LogoFaceShape(face: .top)
                    .fill(.black)
                    .offset(y: isAssembled ? 0 : -54)
                    .scaleEffect(isAssembled ? 1 : 0.78)
                    .opacity(isAssembled ? 1 : 0)
                    .animation(.spring(response: 0.68, dampingFraction: 0.74), value: isAssembled)

                LogoFaceShape(face: .left)
                    .fill(.black)
                    .offset(x: isAssembled ? 0 : -58, y: isAssembled ? 0 : 28)
                    .scaleEffect(isAssembled ? 1 : 0.82, anchor: .topTrailing)
                    .opacity(isAssembled ? 1 : 0)
                    .animation(.spring(response: 0.74, dampingFraction: 0.78).delay(0.12), value: isAssembled)

                LogoFaceShape(face: .right)
                    .fill(.black)
                    .offset(x: isAssembled ? 0 : 58, y: isAssembled ? 0 : 28)
                    .scaleEffect(isAssembled ? 1 : 0.82, anchor: .topLeading)
                    .opacity(isAssembled ? 1 : 0)
                    .animation(.spring(response: 0.74, dampingFraction: 0.78).delay(0.24), value: isAssembled)
            }
            .frame(width: 200, height: 200)
            .offset(y: isFloating ? -5 : 3)
            .scaleEffect(isExiting ? 0.96 : 1)
            .blur(radius: isExiting ? 1.5 : 0)
        }
        .opacity(isExiting ? 0 : 1)
        .task {
            guard !reduceMotion else {
                isAssembled = true
                return
            }

            try? await Task.sleep(nanoseconds: 80_000_000)
            isAssembled = true
            try? await Task.sleep(nanoseconds: 1_050_000_000)
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                isFloating = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("回见")
    }
}

private struct LogoFaceShape: Shape {
    enum Face {
        case top
        case left
        case right
    }

    let face: Face

    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: rect.minX + rect.width * x / 1024,
                y: rect.minY + rect.height * y / 1024
            )
        }

        var path = Path()

        switch face {
        case .top:
            path.move(to: point(122, 248))
            path.addLine(to: point(458, 80))
            path.addQuadCurve(to: point(566, 80), control: point(512, 52))
            path.addLine(to: point(902, 248))
            path.addQuadCurve(to: point(902, 316), control: point(930, 282))
            path.addLine(to: point(566, 484))
            path.addQuadCurve(to: point(458, 484), control: point(512, 512))
            path.addLine(to: point(122, 316))
            path.addQuadCurve(to: point(122, 248), control: point(94, 282))

        case .left:
            path.move(to: point(72, 372))
            path.addLine(to: point(424, 548))
            path.addQuadCurve(to: point(470, 622), control: point(470, 578))
            path.addLine(to: point(470, 952))
            path.addQuadCurve(to: point(396, 997), control: point(430, 1010))
            path.addLine(to: point(60, 829))
            path.addQuadCurve(to: point(14, 755), control: point(14, 790))
            path.addLine(to: point(14, 423))
            path.addQuadCurve(to: point(72, 372), control: point(14, 350))

        case .right:
            path.move(to: point(952, 372))
            path.addLine(to: point(600, 548))
            path.addQuadCurve(to: point(554, 622), control: point(554, 578))
            path.addLine(to: point(554, 952))
            path.addQuadCurve(to: point(628, 997), control: point(594, 1010))
            path.addLine(to: point(964, 829))
            path.addQuadCurve(to: point(1010, 755), control: point(1010, 790))
            path.addLine(to: point(1010, 423))
            path.addQuadCurve(to: point(952, 372), control: point(1010, 350))
        }

        path.closeSubpath()
        return path
    }
}
