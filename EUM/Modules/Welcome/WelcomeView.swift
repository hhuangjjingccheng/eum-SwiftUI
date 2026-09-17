import SwiftUI

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
