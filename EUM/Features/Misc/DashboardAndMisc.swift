import SwiftUI

// MARK: - Dashboard

struct DashboardView: View {
    @EnvironmentObject var app: AppState
    @State private var count = 0

    private let stats: [(String, String, String)] = [
        ("dashboard.stat.users", "1,234", "person"),
        ("dashboard.stat.visits", "567", "eye"),
        ("dashboard.stat.orders", "890", "cart"),
        ("dashboard.stat.revenue", "¥12,345", "cash"),
    ]

    var body: some View {
        PageLayout(header: header) {
            VStack(spacing: 20) {
                // 统计卡片（宽屏多列网格，窄屏单列）
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                    ForEach(stats, id: \.0) { stat in
                        WireStatCard(title: L(stat.0), value: stat.1, icon: stat.2)
                    }
                }

                // 快捷操作
                WireCard(title: L("dashboard.quickActions")) {
                    VStack(alignment: .leading, spacing: 10) {
                        WireButton(title: String(format: L("dashboard.counter"), count), variant: .primary) {
                            withAnimation { count += 1 }
                        }
                        WireButton(title: L("dashboard.addData"), variant: .defaultPlain) {
                            app.toastInfo(L("dashboard.mockAdd"))
                        }
                        WireButton(title: L("dashboard.viewReports"), variant: .ghost) {
                            app.toastInfo(L("dashboard.mockReports"))
                        }
                        WireButton(title: L("dashboard.systemSettings"), variant: .defaultPlain) {
                            app.navigate(to: .eumConfig)
                        }
                        .frame(maxWidth: 240, alignment: .leading)
                    }
                    .padding(16)
                }
            }
        }
    }

    private var header: some View {
        WirePageHeader(
            title: L("dashboard.title"),
            description: L("dashboard.subtitle")
        )
    }
}

// MARK: - 欢迎页

struct WelcomeView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Theme.pageBG.ignoresSafeArea()
                // 光晕
                Circle()
                    .fill(Color(hex: 0x6366F1).opacity(0.12))
                    .frame(width: 380, height: 380)
                    .blur(radius: 60)
                    .offset(x: -proxy.size.width / 2.4, y: -proxy.size.height / 3.2)
                Circle()
                    .fill(Color(hex: 0x06B6D4).opacity(0.12))
                    .frame(width: 340, height: 340)
                    .blur(radius: 60)
                    .offset(x: proxy.size.width / 2.4, y: proxy.size.height / 3.2)

                VStack(spacing: 22) {
                    // 渐变方块 + 弹跳字母
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(LinearGradient(
                                colors: [Color(hex: 0x6366F1), Color(hex: 0x818CF8)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 64, height: 64)
                        HStack(spacing: 1) {
                            ForEach(Array("EUM".enumerated()), id: \.offset) { i, ch in
                                Text(String(ch))
                                    .font(.system(size: 20, weight: .heavy))
                                    .foregroundColor(.white)
                                    .bouncing(delay: Double(i) * 0.12)
                            }
                        }
                    }
                    .padding(16)
                    .background(
                        Circle().stroke(Color(hex: 0x6366F1).opacity(0.2), lineWidth: 1).padding(6)
                    )

                    VStack(spacing: 8) {
                        Text(L("welcome.title"))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(Theme.text)
                        Text(L("auth.brand.headline"))
                            .font(.system(size: 13))
                            .kerning(1)
                            .foregroundColor(Color(hex: 0x909399))
                    }

                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, Theme.border, .clear], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 160, height: 1)

                    Button {
                        if app.isLoggedIn { app.navigate(to: .dashboard) } else { app.authPath = .login }
                    } label: {
                        HStack(spacing: 6) {
                            Text(app.isLoggedIn ? L("welcome.goWorkspace") : L("welcome.goLogin"))
                                .font(.system(size: 14, weight: .medium))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(LinearGradient(
                            colors: [Color(hex: 0x6366F1), Color(hex: 0x818CF8)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(RoundedCorner(radius: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding(40)
                .background(
                    Theme.panelBG.clipShape(RoundedCorner(radius: 24)).panelShadow()
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.borderLight, lineWidth: 1))
                )
                .padding(24)
            }
        }
    }
}

private struct BouncingLetter: ViewModifier {
    let delay: Double
    @State private var up = false
    func body(content: Content) -> some View {
        content
            .offset(y: up ? -4 : 2)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true).delay(delay)) {
                    up = true
                }
            }
    }
}

private extension View {
    func bouncing(delay: Double) -> some View { modifier(BouncingLetter(delay: delay)) }
}

// MARK: - 404 / 403 / 开发中

struct NotFoundView: View {
    @EnvironmentObject var app: AppState
    private let accent = Color(hex: 0x667EEA)

    var body: some View {
        errorScaffold(code: "404", message: L("errors.notFoundDesc"), accent: accent)
    }
}

struct ForbiddenView: View {
    @EnvironmentObject var app: AppState
    private let accent = Color(hex: 0xFF6B6B)

    var body: some View {
        errorScaffold(code: "403", message: L("errors.forbiddenDesc"), accent: accent)
    }
}

private extension View {
    func errorScaffold(code: String, message: String, accent: Color) -> some View {
        ZStack {
            Color(hex: 0xF5F5F5).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(code)
                    .font(.system(size: 90, weight: .bold))
                    .foregroundColor(accent)
                Text(message)
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: 0x666666))
                    .padding(.bottom, 8)
                Button {
                    AppState.shared.navigate(to: .dashboard)
                } label: {
                    Text(L("errors.backHome"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 30)
                        .padding(.vertical, 12)
                        .background(accent)
                        .clipShape(RoundedCorner(radius: 5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct UnderDevelopmentView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [Color(hex: 0x6366F1), Color(hex: 0x818CF8)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 56, height: 56)
                Image(systemName: "terminal")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }
            VStack(spacing: 6) {
                Text(L("route.wip"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.text)
                Text(L("errors.wipDesc"))
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
            }
            HStack(spacing: 12) {
                WireButton(title: L("errors.backWelcome"), icon: "home", variant: .primary) {
                    app.navigate(to: .welcome)
                }
                WireButton(title: L("errors.back"), icon: "back", variant: .ghost) {
                    app.navigate(to: .dashboard)
                }
            }
        }
        .padding(32)
    }
}
