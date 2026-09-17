import SwiftUI

// MARK: - 认证页分栏布局（对应 AuthLayout：左侧线框占位图 + 右侧表单列）

struct AuthSplitLayout<Content: View>: View {
    var reversed = false
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            if proxy.size.width >= 768 {
                HStack(spacing: 0) {
                    if reversed {
                        formColumn
                        placeholderPanel
                    } else {
                        placeholderPanel
                        formColumn
                    }
                }
            } else {
                VStack(spacing: 0) {
                    placeholderPanel
                        .frame(height: 220)
                    formColumn
                }
            }
        }
        .background(.white)
    }

    /// 灰底 + 线框十字占位图
    private var placeholderPanel: some View {
        ZStack {
            Color(hex: 0xE5E7EB)
            // 手绘线框十字
            ZStack {
                RoundedRectangle(cornerRadius: 0)
                    .stroke(.white, lineWidth: 36)
                    .frame(maxWidth: 440, maxHeight: 440)
                    .aspectRatio(1, contentMode: .fit)
                Rectangle().fill(.white).frame(width: 7).frame(maxHeight: 560).rotationEffect(.degrees(45))
                Rectangle().fill(.white).frame(width: 7).frame(maxHeight: 560).rotationEffect(.degrees(-45))
            }
            .padding(24)
            .opacity(0.9)
        }
    }

    private var formColumn: some View {
        ScrollView(showsIndicators: false) {
            content
                .padding(.horizontal, 40)
                .padding(.vertical, 36)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// MARK: - Carbon 风格输入框

struct CarbonTextField: View {
    var title: String
    var placeholder: String
    @Binding var text: String
    var secure: Bool = false
    var showEyeToggle: Bool = false
    @State private var reveal = false
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.authText)
            HStack(spacing: 8) {
                if secure && !reveal {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .autocapitalization(.none)
                        .textInputAutocapitalization(.never)
                }
                if showEyeToggle {
                    Button {
                        reveal.toggle()
                    } label: {
                        WireIcon.image(reveal ? "eye" : "eye-off", size: 18, color: Theme.authHint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(Theme.authFieldBG)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(text.isEmpty ? Color(hex: 0xC1C7CD) : Theme.authBlue)
                    .frame(height: 1)
            }
        }
    }
}

// MARK: - Carbon 主按钮

struct CarbonPrimaryButton: View {
    let title: String
    var loadingTitle: String? = nil
    var loading: Bool = false
    var outlined: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if loading {
                    ProgressView()
                        .tint(outlined ? Theme.authBlue : .white)
                        .scaleEffect(0.8)
                }
                Text(loading ? (loadingTitle ?? title) : title)
                    .font(.system(size: 15, weight: .medium))
                    .kerning(0.4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .foregroundColor(outlined ? Theme.authBlue : .white)
            .background(outlined ? Color.clear : Theme.authBlue)
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .stroke(Theme.authBlue, lineWidth: outlined ? 1.6 : 0)
            )
        }
        .disabled(loading)
        .opacity(loading ? 0.7 : 1)
    }
}

// MARK: - 登录页

struct LoginView: View {
    @EnvironmentObject var app: AppState
    @State private var username = ""
    @State private var password = ""
    @State private var rememberMe = false
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        AuthSplitLayout {
            VStack(alignment: .leading, spacing: 24) {
                Text(L("auth.login.title"))
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(Theme.authText)


                VStack(spacing: 16) {
                    CarbonTextField(title: L("auth.login.email"), placeholder: L("auth.login.emailPlaceholder"), text: $username, keyboard: .emailAddress)
                    VStack(alignment: .leading, spacing: 6) {
                        CarbonTextField(title: L("auth.login.password"), placeholder: L("auth.login.passwordPlaceholder"), text: $password, secure: true, showEyeToggle: true)
                        Text(L("auth.login.passwordTip"))
                            .font(.system(size: 11))
                            .foregroundColor(Theme.authHint)
                    }
                }

                HStack {
                    Button {
                        rememberMe.toggle()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: rememberMe ? "checkmark.square.fill" : "square")
                                .font(.system(size: 15))
                                .foregroundColor(rememberMe ? Theme.authBlue : Color(hex: 0x121619))
                            Text(L("auth.login.rememberMe"))
                                .font(.system(size: 13))
                                .foregroundColor(Theme.authText)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button {
                        app.authPath = .forgot
                    } label: {
                        Text(L("auth.login.forgotPassword"))
                            .font(.system(size: 13))
                            .foregroundColor(Theme.authLink)
                    }
                    .buttonStyle(.plain)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.danger)
                }

                CarbonPrimaryButton(
                    title: L("auth.login.submit"),
                    loadingTitle: L("auth.login.loading"),
                    loading: loading,
                    action: doLogin
                )

                HStack(spacing: 16) {
                    socialButton(L("auth.login.withGoogle"), icon: "g.circle.fill")
                    socialButton(L("auth.login.withApple"), icon: "apple.logo")
                }

                Rectangle().fill(Color(hex: 0xDDE1E6)).frame(height: 1)

                HStack(spacing: 4) {
                    Text(L("auth.login.noAccount"))
                        .font(.system(size: 13))
                        .foregroundColor(Theme.authLink)
                    Button {
                        app.authPath = .register
                    } label: {
                        Text(L("auth.register.title"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.authBlue)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button {
                        app.showDeviceApply = true
                    } label: {
                        Text(L("auth.deviceApply"))
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textTertiary)
                    }
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func socialButton(_ title: String, icon: String) -> some View {
        Button(action: { app.toastInfo(L("auth.social.mock")) }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .foregroundColor(Theme.authBlue)
            .overlay(RoundedRectangle(cornerRadius: 0).stroke(Theme.authBlue, lineWidth: 1.4))
        }
    }

    private func doLogin() {
        errorMessage = nil
        loading = true
        Task {
            defer { loading = false }
            do {
                try await app.login(username: username, password: password)
            } catch {
                errorMessage = (error as? MockError)?.message ?? L("auth.login.failed")
            }
        }
    }
}

// MARK: - 注册页

struct RegisterView: View {
    @EnvironmentObject var app: AppState
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var username = ""
    @State private var password = ""
    @State private var agreed = false
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        AuthSplitLayout(reversed: true) {
            VStack(alignment: .leading, spacing: 24) {
                Text(L("auth.register.title"))
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(Theme.authText)

                VStack(spacing: 16) {
                    HStack(spacing: 16) {
                        CarbonTextField(title: L("auth.register.firstName"), placeholder: L("auth.register.firstName"), text: $firstName)
                        CarbonTextField(title: L("auth.register.lastName"), placeholder: L("auth.register.lastName"), text: $lastName)
                    }
                    CarbonTextField(title: L("auth.register.email"), placeholder: L("auth.register.emailPlaceholder"), text: $username, keyboard: .emailAddress)
                    CarbonTextField(title: L("auth.register.password"), placeholder: L("auth.register.passwordPlaceholder"), text: $password, secure: true, showEyeToggle: true)
                }

                Button {
                    agreed.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: agreed ? "checkmark.square.fill" : "square")
                            .font(.system(size: 15))
                            .foregroundColor(agreed ? Theme.authBlue : Color(hex: 0x121619))
                        Text(L("auth.register.terms"))
                            .font(.system(size: 12))
                            .foregroundColor(Theme.authHint)
                    }
                }
                .buttonStyle(.plain)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.danger)
                }

                CarbonPrimaryButton(title: L("auth.register.submit"), loadingTitle: L("auth.register.loading"), loading: loading, action: doSignUp)

                HStack(spacing: 16) {
                    socialButton(L("auth.login.withGoogle"), icon: "g.circle.fill")
                    socialButton(L("auth.login.withApple"), icon: "apple.logo")
                }

                Rectangle().fill(Color(hex: 0xDDE1E6)).frame(height: 1)

                HStack(spacing: 4) {
                    Text(L("auth.register.haveAccount"))
                        .font(.system(size: 13))
                        .foregroundColor(Theme.authLink)
                    Button {
                        app.authPath = .login
                    } label: {
                        Text(L("auth.login.title"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.authBlue)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func socialButton(_ title: String, icon: String) -> some View {
        Button(action: { app.toastInfo(L("auth.social.mockRegister")) }) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 20))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .foregroundColor(Theme.authBlue)
            .overlay(RoundedRectangle(cornerRadius: 0).stroke(Theme.authBlue, lineWidth: 1.4))
        }
    }

    private func doSignUp() {
        errorMessage = nil
        if firstName.isEmpty || lastName.isEmpty {
            errorMessage = L("auth.message.enterFirstLastName")
            return
        }
        if username.isEmpty {
            errorMessage = L("auth.message.enterEmail")
            return
        }
        if password.isEmpty {
            errorMessage = L("auth.message.enterPassword")
            return
        }
        guard agreed else {
            errorMessage = L("auth.message.agreeTerms")
            return
        }
        loading = true
        Task {
            defer { loading = false }
            do {
                try await app.register(username: username, password: password)
                app.toastSuccess(L("auth.register.success.title"))
                app.authPath = .login
            } catch {
                errorMessage = (error as? MockError)?.message ?? L("auth.register.failed")
            }
        }
    }
}

// MARK: - 忘记密码（独立页，非 AuthLayout）

struct ForgotPasswordView: View {
    @EnvironmentObject var app: AppState
    @State private var email = ""
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.authFieldBG.ignoresSafeArea()

            VStack {
                Button {
                    app.authPath = .login
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left")
                        Text(L("auth.forgot.backToLogin"))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.authBlue)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 20) {
                    Text(L("auth.forgot.title"))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(Theme.authText)
                    Text(L("auth.forgot.subtitle"))
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: 0x4D5358))
                        .fixedSize(horizontal: false, vertical: true)

                    CarbonTextField(title: L("auth.forgot.email"), placeholder: L("auth.forgot.emailPlaceholder"), text: $email, keyboard: .emailAddress)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.danger)
                    }

                    CarbonPrimaryButton(title: L("auth.forgot.submit"), loadingTitle: L("auth.forgot.sending"), loading: loading, action: doSend)
                }
                .padding(40)
                .background(.white)
                .clipShape(RoundedCorner(radius: 0))
                .panelShadow()
                .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .navigationBarHidden(true)
    }

    private func doSend() {
        errorMessage = nil
        guard !email.isEmpty else {
            errorMessage = L("auth.message.enterEmail")
            return
        }
        loading = true
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            loading = false
            app.toastSuccess(L("auth.forgot.success"))
            app.authPath = .login
        }
    }
}
