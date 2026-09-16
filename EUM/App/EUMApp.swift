import SwiftUI

@main
struct EUMApp: App {
    @StateObject private var app = AppState.shared
    @StateObject private var store = DataService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(store)
                .preferredColorScheme(.light)
                .modifier(RootWindowMinSize())
        }
    }
}

/// 最小窗口尺寸仅约束 Mac Catalyst 桌面窗口；
/// iPhone / iPad 必须完全跟随屏幕尺寸，否则内容被撑到 900pt 宽导致左右裁切。
private struct RootWindowMinSize: ViewModifier {
    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content.frame(minWidth: 900, minHeight: 600)
        #else
        content
        #endif
    }
}

struct RootView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        Group {
            if app.isLoggedIn {
                MainLayout()
            } else {
                switch app.authPath {
                case .login: LoginView()
                case .register: RegisterView()
                case .forgot: ForgotPasswordView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.isLoggedIn)
        .animation(.easeInOut(duration: 0.2), value: app.authPath)
    }
}
