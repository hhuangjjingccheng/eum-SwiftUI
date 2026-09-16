import SwiftUI

// MARK: - 页面工厂

struct RoutePageFactory: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .welcome: WelcomeView()
        case .dashboard: DashboardView()
        case .userInfo: ProfileView()
        case .eumUser: EumUserView()
        case .eumAccount: AccountView()
        case .eumRole: EumRoleView()
        case .eumMenu: EumMenuView()
        case .eumDept: EumDeptView()
        case .eumPost: EumPostView()
        case .eumDict: EumDictView()
        case .eumConfig: EumConfigView()
        case .eumAI: AIConfigView()
        case .eumFxshell: FxshellView()
        case .eumDataPermission: DataPermissionView()
        case .eumAuditLog: AuditLogView()
        case .bizCustomer: BizCustomerView()
        case .bizOrder: BizOrderView()
        case .toolCalcite: CalciteView()
        case .toolLangGraph: LangGraphView()
        case .uralytUser: UralytUserView()
        case .uralytUric: UricRecordView()
        case .uralytMedical: MedicalRecordView()
        case .chat: ChatView()
        case .appLicense: LicenseView()
        case .appDevice: DeviceView()
        case .appPlugin: PluginView()
        case .notFound: NotFoundView()
        case .forbidden: ForbiddenView()
        case .underDevelopment: UnderDevelopmentView()
        }
    }
}

// MARK: - 主布局

struct MainLayout: View {
    @EnvironmentObject var app: AppState
    @Environment(\.horizontalSizeClass) private var hSize

    /// 宽屏（iPad / Mac Catalyst / 大屏分屏）：侧边栏常驻双栏
    private var isWide: Bool { hSize == .regular }

    var body: some View {
        Group {
            if isWide {
                HStack(spacing: 0) {
                    sidebarPanel
                        .id(app.i18nVersion)
                    // 侧边栏与内容之间的分隔
                    Rectangle()
                        .fill(Theme.border.opacity(0.6))
                        .frame(width: 1)
                        .padding(.vertical, 12)
                    VStack(spacing: 0) {
                        topBar
                        Rectangle().fill(Theme.border).frame(height: 1)
                        mainArea
                    }
                }
            } else {
                VStack(spacing: 0) {
                    topBar
                    Rectangle().fill(Theme.border).frame(height: 1)
                    mainArea
                }
                .overlay(alignment: .leading) {
                    if app.showSidebar {
                        sidebarDrawer
                    }
                }
            }
        }
        .background(Theme.pageBG)
        .overlay(alignment: .top) { ToastOverlay(toast: app.toast) }
        .sheet(isPresented: $app.showAIAssistant) {
            AIAssistantSheet()
        }
        .sheet(isPresented: $app.showDeviceApply) {
            DeviceApplyView(isSheet: true)
                .environmentObject(app)
        }
    }

    // MARK: 顶栏
    private var topBar: some View {
        HStack(spacing: 12) {
            // Logo 区（窄屏点击弹出侧栏抽屉）
            Button {
                if !isWide { app.showSidebar.toggle() }
            } label: {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Theme.primary)
                            .frame(width: 26, height: 26)
                        Text("E")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundColor(.white)
                    }
                    Text("EUM")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(Color(hex: 0x111827))
                        .kerning(-0.3)
                }
            }
            .buttonStyle(.plain)
            .help(isWide ? "" : L("nav.openMenu"))

            // TagsView
            TagsBarView()
                .id(app.i18nVersion)

            // 通知（AI 助手浮窗入口）
            Button {
                app.showAIAssistant = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    WireIcon.image("notifications", size: 20, color: Color(hex: 0x0F172A))
                    Circle().fill(Color(hex: 0xEF4444)).frame(width: 8, height: 8)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .offset(x: 3, y: -3)
                }
            }
            .buttonStyle(.plain)
            .help(L("ai.assistant"))

            // 用户菜单
            Menu {
                Button {
                    app.navigate(to: .userInfo)
                } label: {
                    Label(L("nav.profile"), systemImage: "person")
                }
                Divider()
                Button(role: .destructive) {
                    app.logout()
                } label: {
                    Label(L("nav.logout"), systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                HStack(spacing: 6) {
                    Text(String(app.displayName.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: 0x64748B))
                        .frame(width: 30, height: 30)
                        .background(Color(hex: 0xF1F5F9))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color(hex: 0xE2E8F0), lineWidth: 1))
                    if isWide {
                        Text(app.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Theme.text)
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(Theme.panelBG)
    }

    // MARK: 主内容区
    private var mainArea: some View {
        ZStack(alignment: .top) {
            RoutePageFactory(route: app.currentRoute)
                .id(app.currentRoute)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .overlay {
            if app.routeSwitching {
                ZStack {
                    Theme.pageBG.opacity(0.65).ignoresSafeArea()
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(L("common.loading"))
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .background(Theme.panelBG)
                    .clipShape(RoundedCorner(radius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                    .panelShadow()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: app.routeSwitching)
    }

    // MARK: 侧边栏（宽屏固定面板）
    private var sidebarPanel: some View {
        SidebarPanel()
            .frame(width: app.sidebarCollapsed ? 64 : 200)
            .padding(12)
    }

    // MARK: 侧边栏（窄屏抽屉）
    private var sidebarDrawer: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { app.showSidebar = false }
            SidebarPanel(isDrawer: true)
                .id(app.i18nVersion)
                .frame(width: 186)   // 原宽度（280）的 2/3
                .padding(.vertical, 10)
                .padding(.leading, 10)
                .transition(.move(edge: .leading))
        }
        .transition(.opacity)
        .animation(.easeOut(duration: 0.2), value: app.showSidebar)
    }
}

// MARK: - 侧边栏面板

struct SidebarPanel: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    /// 抽屉模式（手机端）：固定展开、隐藏折叠按钮、带头部与关闭按钮
    var isDrawer: Bool = false
    @State private var searchText = ""

    /// 抽屉模式不受桌面折叠状态影响（折叠会导致菜单只剩图标）
    private var collapsed: Bool { isDrawer ? false : app.sidebarCollapsed }

    private var nodes: [SidebarNode] {
        let all = app.buildSidebar()
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.matches(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isDrawer {
                drawerHeader
            }
            // 搜索：折叠态缩为图标按钮（点击展开面板）
            if collapsed {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) { app.sidebarCollapsed = false }
                } label: {
                    WireIcon.image("search", size: 15, color: Theme.text)
                        .frame(width: 32, height: 32)
                        .background(Color(hex: 0xF1F5F9))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            } else {
                // 搜索框
                HStack(spacing: 6) {
                    WireIcon.image("search", size: 14, color: Theme.textTertiary)
                    TextField(L("common.search"), text: $searchText)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(hex: 0xF1F5F9))
                .clipShape(RoundedCorner(radius: 6))
                .padding(.horizontal, 10)
                .padding(.top, 10)
            }

            // 菜单
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(nodes) { node in
                        if node.children.isEmpty {
                            leafItem(node, indent: 14)
                        } else {
                            DisclosureGroupWidget(node: node, parentCollapsed: collapsed)
                        }
                    }
                    if store.menus.isEmpty {
                        if collapsed {
                            Image(systemName: "tray")
                                .font(.system(size: 20))
                                .foregroundColor(Theme.textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 30)
                        } else {
                            emptyMenuHint
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }

            // 底部折叠按钮（仅桌面固定面板；抽屉折叠会让菜单失去文字）
            if !isDrawer {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        app.sidebarCollapsed.toggle()
                    }
                } label: {
                    WireIcon.image("list", size: 18, color: Theme.textSecondary)
                        .rotationEffect(.degrees(app.sidebarCollapsed ? 180 : 0))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) { Rectangle().fill(Theme.borderLight).frame(height: 1) }
            }
        }
        .background(Theme.panelBG)
        .clipShape(RoundedCorner(radius: Theme.panelRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.panelRadius).stroke(Theme.border, lineWidth: 1))
        .panelShadow()
    }

    /// 抽屉头部：品牌 + 关闭
    private var drawerHeader: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.primary)
                    .frame(width: 26, height: 26)
                Text("E")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(.white)
            }
            Text("EUM")
                .font(.system(size: 18, weight: .heavy))
                .foregroundColor(Color(hex: 0x111827))
                .kerning(-0.3)
            Spacer()
            Button {
                app.showSidebar = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(Color(hex: 0xF3F4F6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    /// 服务端菜单未加载时的占位提示
    private var emptyMenuHint: some View {
        VStack(spacing: 6) {
            Text(L("nav.noMenus"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.textSecondary)
            Text(L("nav.noMenusHint"))
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func leafItem(_ node: SidebarNode, indent: CGFloat) -> some View {
        let isActive = app.currentRoute == node.route
        return Button {
            if let r = node.route {
                app.navigate(to: r)
            } else if let url = node.externalURL {
                // 外链菜单（对齐 web：新窗口打开）
                UIApplication.shared.open(url)
            }
        } label: {
            Group {
                if collapsed {
                    WireIcon.image(node.icon, size: 16, color: isActive ? Color(hex: 0x111827) : Color(hex: 0x6B7280))
                        .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 8) {
                        WireIcon.image(node.icon, size: 16, color: isActive ? Color(hex: 0x111827) : Color(hex: 0x6B7280))
                        Text(node.title)
                            .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                            .foregroundColor(isActive ? Color(hex: 0x111827) : Color(hex: 0x4B5563))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, indent)
                    .padding(.trailing, 10)
                }
            }
            .frame(height: 38)
            .frame(maxWidth: .infinity)
            .background(isActive ? Color(hex: 0xF3F4F6) : .clear)
            .clipShape(RoundedCorner(radius: 6))
        }
        .buttonStyle(.plain)
        .help(collapsed ? node.title : "")
    }

    /// 可展开目录
    private struct DisclosureGroupWidget: View {
        @EnvironmentObject var app: AppState
        let node: SidebarNode
        /// 跟随面板折叠状态（抽屉模式下由父级固定为 false）
        let parentCollapsed: Bool
        @State private var expanded = false

        /// 目录激活 = 当前路由在子级中
        private var isChildActive: Bool {
            node.children.contains { $0.route == app.currentRoute }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    if parentCollapsed {
                        // 折叠态：点目录图标展开面板
                        withAnimation(.easeInOut(duration: 0.3)) { app.sidebarCollapsed = false }
                    } else {
                        withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
                    }
                } label: {
                    Group {
                        if parentCollapsed {
                            WireIcon.image(node.icon, size: 16, color: isChildActive ? Color(hex: 0x111827) : Color(hex: 0x6B7280))
                                .frame(maxWidth: .infinity)
                        } else {
                            HStack(spacing: 8) {
                                WireIcon.image(node.icon, size: 16, color: isChildActive ? Color(hex: 0x111827) : Color(hex: 0x6B7280))
                                Text(node.title)
                                    .font(.system(size: 13, weight: isChildActive ? .semibold : .medium))
                                    .foregroundColor(isChildActive ? Color(hex: 0x111827) : Color(hex: 0x4B5563))
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Theme.textTertiary)
                                    .rotationEffect(.degrees(expanded ? 90 : 0))
                            }
                            .padding(.horizontal, 10)
                        }
                    }
                    .frame(height: 38)
                    .frame(maxWidth: .infinity)
                    .background(isChildActive ? Color(hex: 0xF3F4F6) : .clear)
                    .clipShape(RoundedCorner(radius: 6))
                }
                .buttonStyle(.plain)
                .help(parentCollapsed ? node.title : "")

                if expanded && !parentCollapsed {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(node.children) { child in
                            childLeaf(child)
                        }
                    }
                    .padding(.leading, 16)
                }
            }
        }

        private func childLeaf(_ child: SidebarNode) -> some View {
            let isActive = app.currentRoute == child.route
            return Button {
                if let r = child.route { app.navigate(to: r) }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isActive ? Theme.primary : Theme.border)
                        .frame(width: 5, height: 5)
                    Text(child.title)
                        .font(.system(size: 12.5, weight: isActive ? .semibold : .regular))
                        .foregroundColor(isActive ? Color(hex: 0x111827) : Color(hex: 0x6B7280))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 14)
                .padding(.trailing, 10)
                .frame(height: 34)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isActive ? Color(hex: 0xF3F4F6) : .clear)
                .clipShape(RoundedCorner(radius: 6))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - 顶栏标签栏（TagsView）

struct TagsBarView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(app.visitedTags) { tag in
                    tagView(tag)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func tagView(_ tag: VisitTag) -> some View {
        let isActive = app.currentRoute == tag.route
        return Button {
            app.navigate(to: tag.route)
        } label: {
            HStack(spacing: 5) {
                Text(tag.title)
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                    .foregroundColor(isActive ? Theme.primary : Theme.textSecondary)
                    .lineLimit(1)
                if tag.route != .dashboard {
                    Button {
                        app.closeTag(tag)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Theme.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isActive ? Theme.primaryLight9 : .clear)
            .clipShape(RoundedCorner(radius: 6))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                app.closeOtherTags(keeping: tag)
            } label: {
                Label(L("nav.closeOthers"), systemImage: "xmark.circle")
            }
        }
    }
}

// MARK: - AI 助手浮窗（对应 FloatingWindow）

struct AIAssistantSheet: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ChatView()
                .navigationTitle(L("ai.assistant"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L("common.close")) { dismiss() }
                            .font(.system(size: 13))
                    }
                }
        }
        .environmentObject(app)
    }
}
