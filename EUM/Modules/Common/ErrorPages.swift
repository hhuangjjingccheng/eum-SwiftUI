import SwiftUI

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
