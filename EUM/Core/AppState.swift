import SwiftUI
import Combine

// MARK: - 路由

/// 应用路由（对应 eum-front 动态路由中的静态映射）
enum AppRoute: String, CaseIterable, Identifiable, Hashable {
    case welcome
    case dashboard
    case userInfo
    case eumUser, eumRole, eumMenu, eumDept, eumPost, eumDict, eumConfig, eumAI
    case eumAccount, eumFxshell, eumDataPermission, eumAuditLog
    case bizCustomer, bizOrder
    case toolCalcite, toolLangGraph
    case uralytUser, uralytUric, uralytMedical
    case chat
    case appLicense, appDevice, appPlugin
    case notFound, forbidden, underDevelopment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .welcome: return L("route.welcome")
        case .dashboard: return L("route.dashboard")
        case .userInfo: return L("route.userInfo")
        case .eumUser: return I18n.t("eum.user")
        case .eumAccount: return L("route.account")
        case .eumRole: return I18n.t("eum.role")
        case .eumMenu: return I18n.t("eum.menu")
        case .eumDept: return I18n.t("eum.dept")
        case .eumPost: return I18n.t("eum.post")
        case .eumDict: return I18n.t("eum.dict")
        case .eumConfig: return L("config.title")
        case .eumAI: return I18n.t("eum.ai")
        case .eumFxshell: return L("route.fxshell")
        case .eumDataPermission: return L("route.dataPermission")
        case .eumAuditLog: return L("route.auditLog")
        case .bizCustomer: return L("route.customer")
        case .bizOrder: return L("route.order")
        case .toolCalcite: return L("route.calcite")
        case .toolLangGraph: return L("route.langgraph")
        case .uralytUser: return I18n.t("uralyt-u.user")
        case .uralytUric: return I18n.t("uralyt-u.uric")
        case .uralytMedical: return I18n.t("uralyt-u.medical")
        case .chat: return L("route.chat")
        case .appLicense: return L("route.license")
        case .appDevice: return L("route.device")
        case .appPlugin: return L("route.plugin")
        case .notFound: return L("route.notFound")
        case .forbidden: return L("route.forbidden")
        case .underDevelopment: return L("route.wip")
        }
    }

    var icon: String {
        switch self {
        case .welcome: return "sparkles"
        case .dashboard: return "dashboard"
        case .userInfo: return "user"
        case .eumUser: return "user"
        case .eumAccount: return "user"
        case .eumRole: return "userfilled"
        case .eumMenu: return "menu"
        case .eumDept: return "share"
        case .eumPost: return "postcard"
        case .eumDict: return "collection"
        case .eumConfig: return "operation"
        case .eumAI: return "cpu"
        case .eumFxshell: return "bug"
        case .eumDataPermission: return "shield"
        case .eumAuditLog: return "document"
        case .bizCustomer: return "team"
        case .bizOrder: return "receipt"
        case .toolCalcite: return "database"
        case .toolLangGraph: return "flow"
        case .uralytUser: return "user"
        case .uralytUric: return "histogram"
        case .uralytMedical: return "firstaidkit"
        case .chat: return "chatlineround"
        case .appLicense: return "key"
        case .appDevice: return "monitor"
        case .appPlugin: return "connection"
        case .notFound, .forbidden: return "exclamationmark.triangle"
        case .underDevelopment: return "wrench.and.screwdriver"
        }
    }
}

/// 侧边栏菜单节点（由后端菜单树转换）
struct SidebarNode: Identifiable, Equatable {
    let id: Int
    let title: String
    let icon: String
    let route: AppRoute?
    let externalURL: URL?
    let children: [SidebarNode]

    /// 目录节点是否命中搜索（父命中保留全部子级；子命中保留父）
    func matches(_ keyword: String) -> Bool {
        guard !keyword.isEmpty else { return true }
        if title.localizedCaseInsensitiveContains(keyword) { return true }
        return children.contains { $0.matches(keyword) }
    }
}

// MARK: - 顶栏标签（TagsView）

struct VisitTag: Identifiable, Equatable {
    let route: AppRoute
    var id: String { route.rawValue }
    var title: String { route.title }
}

// MARK: - Toast

struct ToastMessage: Equatable, Identifiable {
    enum Kind { case success, error, info, warning }
    let id = UUID()
    let text: String
    let kind: Kind
}

// MARK: - 认证流程导航

enum AuthPath: String {
    case login, register, forgot
}

// MARK: - 全局状态

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    // 认证
    @Published var isLoggedIn: Bool = APIClient.shared.token != nil
    @Published var authPath: AuthPath = .login
    @Published var currentUser = SysUser(id: 0, username: "", nickName: "")

    init() {
        // 支持命令行启动参数（用于自动化验证）：-skipLogin / -route <route> / -openDrawer
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-skipLogin") {
            isLoggedIn = true
        }
        if args.contains("-openDrawer") {
            showSidebar = true
        }
        if args.contains("-collapseSidebar") {
            sidebarCollapsed = true
        }
        // 调试：-themeColor <hex> 覆盖主题色（模拟 sys/config 下发的 themeColor）
        if let i = args.firstIndex(of: "-themeColor"), i + 1 < args.count {
            Theme.applyThemeColor(args[i + 1])
        }
        // 调试：-language <code> 覆盖界面语言（模拟 sys/config 下发，内置兜底词表生效）
        if let i = args.firstIndex(of: "-language"), i + 1 < args.count {
            I18n.apply(languageJson: DataService.shared.sysConfig.languageJson, language: args[i + 1])
        }
        if let i = args.firstIndex(of: "-route"), i + 1 < args.count,
           let route = AppRoute(rawValue: args[i + 1]) {
            currentRoute = route
            visitedTags = [VisitTag(route: route)]
        }
        // 内置兜底词表先行（无网络时登录 / 注册页也有中英文），随后服务端词条覆盖
        I18n.apply(languageJson: DataService.shared.sysConfig.languageJson, language: "system")

        // 启动即调用 /sys/config/getConfig（免认证）：登录 / 注册页的主题色与多语言首屏生效；
        // 已有 token 时继续静默恢复会话
        Task { [weak self] in
            await DataService.shared.loadSysConfig()
            guard let self, isLoggedIn else { return }
            await self.restoreSession()
        }
    }

    // 路由 / 标签页
    @Published var currentRoute: AppRoute = .dashboard
    @Published var visitedTags: [VisitTag] = [VisitTag(route: .dashboard)]
    @Published var sidebarCollapsed = false
    @Published var showSidebar = false
    /// 路由切换转场：切页瞬间显示加载态，稍后自动淡出
    @Published var routeSwitching = false
    @Published var showAIAssistant = false

    // Toast
    @Published var toast: ToastMessage?

    /// i18n 表加载完成后递增，驱动侧边栏/标签栏刷新翻译
    @Published var i18nVersion = 0

    // 独立流程：设备授权申请（免登录页）
    @Published var showDeviceApply = false

    var displayName: String {
        currentUser.nickName.isEmpty ? (currentUser.username.isEmpty ? "管理员" : currentUser.username) : currentUser.nickName
    }

    // MARK: 会话

    private func restoreSession() async {
        do {
            try await DataService.shared.bootstrap()
            i18nVersion += 1
        } catch {
            // §6 Token 失效（4011~4015）→ 静默回登录页；其余提示
            if let apiErr = error as? APIClient.ApiError {
                if apiErr.isAuthFailure { return }
                toastError(apiErr.message)
            } else {
                toastError("会话恢复失败：\(error.localizedDescription)")
            }
        }
    }

    func handleUnauthorized() {
        guard isLoggedIn else { return }
        APIClient.shared.setToken(nil)
        isLoggedIn = false
        authPath = .login
        visitedTags = [VisitTag(route: .dashboard)]
        currentRoute = .dashboard
    }

    // MARK: 导航
    func navigate(to route: AppRoute) {
        currentRoute = route
        if !visitedTags.contains(where: { $0.route == route }) {
            visitedTags.append(VisitTag(route: route))
        }
        showSidebar = false
        beginRouteSwitch()
    }

    /// 页面切换转场：立即给出加载反馈，短暂后自动结束（页面自身的数据加载由各自 loading 态接管）
    private func beginRouteSwitch() {
        routeSwitching = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            self?.routeSwitching = false
        }
    }

    func closeTag(_ tag: VisitTag) {
        guard tag.route != .dashboard else { return } // 首页标签固定
        visitedTags.removeAll { $0.route == tag.route }
        if currentRoute == tag.route {
            // 回退到最后一个标签
            if let last = visitedTags.last {
                currentRoute = last.route
            }
        }
    }

    func closeOtherTags(keeping tag: VisitTag) {
        visitedTags = visitedTags.filter { $0.route == .dashboard || $0.route == tag.route }
        currentRoute = tag.route
    }

    // MARK: 认证（真实后端）
    func login(username: String, password: String) async throws {
        guard !username.isEmpty else { throw MockError("Please enter email address") }
        guard !password.isEmpty else { throw MockError("Please enter password") }
        _ = try await DataService.shared.login(username: username, password: password)
        // 拉取用户信息 + 菜单 + 配置 + 基础字典
        try await DataService.shared.bootstrap()
        i18nVersion += 1
        isLoggedIn = true
        currentRoute = .dashboard
        visitedTags = [VisitTag(route: .dashboard)]
        toastSuccess(L("auth.login.success"))
    }

    func register(username: String, password: String) async throws {
        guard username.count >= 3 else { throw MockError("Email length cannot be less than 3") }
        guard password.count >= 6 else { throw MockError("Password length cannot be less than 6") }
        try await DataService.shared.register(username: username, password: password)
    }

    func logout() {
        Task { await DataService.shared.logout() }
        handleUnauthorized()
    }

    // MARK: Toast
    func toastSuccess(_ text: String) { showToast(text, kind: .success) }
    func toastError(_ text: String) { showToast(text, kind: .error) }
    func toastInfo(_ text: String) { showToast(text, kind: .info) }
    func toastWarning(_ text: String) { showToast(text, kind: .warning) }

    private var toastTask: Task<Void, Never>?
    func showToast(_ text: String, kind: ToastMessage.Kind) {
        toast = ToastMessage(text: text, kind: kind)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    // MARK: 侧边栏菜单树（由后端菜单树转换，menuName 经 i18n 翻译）
    func buildSidebar() -> [SidebarNode] {
        var nodes: [SidebarNode] = [
            SidebarNode(id: 0, title: L("route.dashboard"), icon: "dashboard", route: .dashboard, externalURL: nil, children: []),
        ]
        func convert(_ menu: SysMenu) -> SidebarNode {
            let kids = menu.children
                .filter { $0.menuType != 3 && $0.visible == 1 && $0.status == 1 }
                .sorted { $0.orderNum < $1.orderNum }
                .map(convert)
            let (route, external) = Self.destination(for: menu)
            return SidebarNode(
                id: menu.id,
                title: menu.translatedName,
                icon: menu.icon,
                route: route,
                externalURL: external,
                children: kids
            )
        }
        nodes += DataService.shared.menus
            .filter { $0.visible == 1 && $0.status == 1 }
            .sorted { $0.orderNum < $1.orderNum }
            .map(convert)
        return nodes
    }

    /// component → 路由 / 外链（未实现页面 → 开发中；http(s) 外链 → Safari 打开）
    private static func destination(for menu: SysMenu) -> (AppRoute?, URL?) {
        let comp = menu.component
        if comp.hasPrefix("http://") || comp.hasPrefix("https://"),
           let url = URL(string: comp) {
            return (nil, url)
        }
        let route: AppRoute?
        switch comp {
        case "eum/user/index": route = .eumUser
        case "eum/account/index": route = .eumAccount
        case "tool/calcite/index": route = .toolCalcite
        case "tool/langgraph/index": route = .toolLangGraph
        case "eum/role/index": route = .eumRole
        case "eum/menu/index": route = .eumMenu
        case "eum/dept/index": route = .eumDept
        case "eum/post/index": route = .eumPost
        case "eum/dict/index": route = .eumDict
        case "eum/config/index": route = .eumConfig
        case "eum/ai/index": route = .eumAI
        case "eum/fxshell/index", "bovinishell/index": route = .eumFxshell
        case "eum/dataPermission/index": route = .eumDataPermission
        case "eum/auditLog/index": route = .eumAuditLog
        case "biz/customer/index": route = .bizCustomer
        case "biz/order/index": route = .bizOrder
        case "uralyt-u/user/index": route = .uralytUser
        case "uralyt-u/uric/index": route = .uralytUric
        case "uralyt-u/medical/index": route = .uralytMedical
        case "Chat": route = .chat
        case "app/license/index": route = .appLicense
        case "app/device/index": route = .appDevice
        case "app/plugin/index": route = .appPlugin
        case "", "Layout": route = nil          // 目录
        default: route = .underDevelopment      // eum/fxshell 等未实现页面
        }
        return (route, nil)
    }
}

extension AppState {
    /// 统一 API 错误提示：优先后端 message（受 Accept-Language 影响），其次 §6 兜底文案
    func toast(_ error: Error, fallback: String) {
        if let apiErr = error as? APIClient.ApiError {
            toastError(apiErr.message)
        } else {
            toastError((error as? LocalizedError)?.errorDescription ?? fallback)
        }
    }
}

struct MockError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
