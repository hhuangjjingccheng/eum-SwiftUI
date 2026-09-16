import SwiftUI

// MARK: - 数据权限管理（eum_data_permission_rule / grant / exception）

struct DataPermissionView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var resourceType = ""
    @State private var rows: [PermissionRule] = []
    @State private var loading = false
    @State private var selected: Set<Int> = []
    @State private var showBatchDelete = false
    @State private var active = "list"
    @State private var tabs: [DynTab] = []
    @State private var mobileForm: MobileTarget?
    /// 弹窗绑定：规则ID + 类型
    @State private var bindingTarget: BindingTarget?

    enum MobileTarget: Identifiable {
        case add, edit(PermissionRule)
        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let rule): return "edit-\(rule.id)"
            }
        }
        var title: String {
            switch self {
            case .add: return "新增数据权限规则"
            case .edit: return "编辑数据权限规则"
            }
        }
    }

    struct BindingTarget: Identifiable {
        let rule: PermissionRule
        let kind: Kind
        enum Kind { case grant, exception }
        var id: String { "\(rule.id)-\(kind == .grant ? "g" : "e")" }
    }

    private var isCompact: Bool { hSize == .compact }

    private var columns: [TableCol] = [
        .init(L("eum.index"), 60, align: .center),
        .init(L("perm.ruleName"), 180),
        .init(L("perm.resourceType"), 140),
        .init(L("perm.grantType"), 100, align: .center),
        .init(L("perm.dataScope"), 160),
        .init(L("eum.status"), 80, align: .center),
        .init(L("eum.remark"), 180),
        .init(L("eum.operation"), 220, align: .center),
    ]

    var body: some View {
        PageLayout(header: headerSection, scrolls: !isCompact) {
            if active == "list" {
                listSection
            } else {
                formAndDetailSections
            }
        }
        .overlay { TableLoadingOverlay(loading: loading) }
        .sheet(item: $bindingTarget) { target in
            RuleBindingSheet(rule: target.rule, kind: target.kind)
                .environmentObject(store)
                .environmentObject(app)
        }
        .task { await load() }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            if isCompact {
                MobileSearchBar(text: $resourceType,
                                placeholder: String(format: L("common.searchFormat"), L("perm.resourceType")),
                                onFilter: {},
                                onSubmit: { Task { await load() } })
            } else {
                QueryForm {
                    QueryField(label: L("perm.resourceType"), text: $resourceType)
                } onSearch: {
                    Task { await load() }
                } onReset: {
                    resourceType = ""
                    Task { await load() }
                }
                DynTabBar(tabs: $tabs, active: $active, fixedTitle: L("list.rules"))
            }
        }
    }

    private var listSection: some View {
        Group {
            if isCompact {
                mobileList
            } else {
                desktopList
            }
        }
        .confirmationDialog(String(format: L("common.confirmDelete"), selected.count), isPresented: $showBatchDelete, titleVisibility: .visible) {
            Button(L("button.delete"), role: .destructive) { Task { await doBatchDelete() } }
            Button(L("button.cancel"), role: .cancel) {}
        }
        .sheet(item: $mobileForm) { target in
            MobileSheetContainer(title: target.title) {
                switch target {
                case .add:
                    PermissionRuleFormView(onClose: { mobileForm = nil }) {
                        mobileForm = nil
                        Task { await load() }
                    }
                case .edit(let rule):
                    PermissionRuleFormView(rule: rule, onClose: { mobileForm = nil }) {
                        mobileForm = nil
                        Task { await load() }
                    }
                }
            }
        }
    }

    private var mobileList: some View {
        ZStack(alignment: .bottomTrailing) {
            MobileCardList(
                cards: rows.map(mobileCard),
                total: rows.count,
                selection: $selected,
                batchActions: [
                    .init(title: L("button.batchDelete"), role: .danger) { showBatchDelete = true },
                ],
                onLoadMore: nil,
                hasMore: false
            )
            if selected.isEmpty {
                MobileFAB { mobileForm = .add }
                    .padding(.trailing, 16)
                    .padding(.bottom, 18)
            }
        }
    }

    private func mobileCard(for rule: PermissionRule) -> MobileCardModel {
        MobileCardModel(
            id: rule.id,
            title: rule.ruleName,
            subtitle: rule.resourceType.isEmpty ? "未指定资源类型" : "资源类型：\(rule.resourceType)",
            initials: String(rule.ruleName.prefix(1)),
            showBadge: true,
            badgeText: rule.status == 1 ? L("eum.status.enable") : L("eum.status.disable"),
            badgeKind: rule.status == 1 ? .success : .danger,
            fields: [
                .init(label: L("perm.grantType"), value: rule.permissionTypeText()),
                .init(label: L("perm.dataScope"), value: rule.dataScopeText()),
                .init(label: L("eum.remark"), value: rule.remark.isEmpty ? "-" : rule.remark),
            ],
            actions: [
                .init(title: L("perm.grant")) { bindingTarget = .init(rule: rule, kind: .grant) },
                .init(title: L("perm.exception")) { bindingTarget = .init(rule: rule, kind: .exception) },
                .init(title: L("button.edit")) { mobileForm = .edit(rule) },
            ]
        )
    }

    private var desktopList: some View {
        WireCard(fullHeight: true) {
            VStack(spacing: 0) {
                toolbar
                WireTable(columns: columns, rowCount: rows.count, selectable: true, selection: selectedIndexes) { idx in
                    onToggleRow(idx)
                } rowAction: { idx in
                    row(idx)
                }
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            WireButton(title: L("perm.addRule"), icon: "add-circle", variant: .primary) {
                active = tabs.open(name: "add-\(Int(Date().timeIntervalSince1970))", title: L("perm.addRule"))
            }
            WireButton(title: L("button.batchDelete"), icon: "delete", variant: .danger, disabled: selected.isEmpty) {
                showBatchDelete = true
            }
            Spacer()
            Text("共 \(rows.count) 条")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
        }
        .padding(12)
    }

    private func row(_ idx: Int) -> some View {
        let rule = rows[idx]
        return HStack(spacing: 0) {
            TableCell(text: "\(idx + 1)", width: 60, align: .center, color: Theme.textSecondary)
            TableCell(text: rule.ruleName, width: 180)
            TableCell(text: rule.resourceType.isEmpty ? "-" : rule.resourceType, width: 140)
            TableCell(text: rule.permissionTypeText(), width: 100, align: .center)
            TableCell(text: rule.dataScopeText(), width: 160)
            HStack { StatusTag(text: rule.status == 1 ? L("eum.status.enable") : L("eum.status.disable"), kind: rule.status == 1 ? .success : .danger) }
                .frame(width: 80, alignment: .center)
            TableCell(text: rule.remark.isEmpty ? "-" : rule.remark, width: 180, color: Theme.textSecondary)
            HStack(spacing: 8) {
                WireButton(title: L("perm.grant"), icon: "key", variant: .linkPrimary, small: true) {
                    bindingTarget = .init(rule: rule, kind: .grant)
                }
                WireButton(title: L("perm.exception"), icon: "exclamationmark.shield", variant: .linkPrimary, small: true) {
                    bindingTarget = .init(rule: rule, kind: .exception)
                }
                WireButton(title: L("button.edit"), icon: "pencil", variant: .linkPrimary, small: true) {
                    active = tabs.open(name: "edit-\(rule.id)", title: String(format: L("tab.edit"), rule.ruleName))
                }
            }
            .frame(width: 220, alignment: .center)
        }
    }

    @ViewBuilder
    private var formAndDetailSections: some View {
        ForEach(tabs) { tab in
            if active == tab.name {
                WireCard(fullHeight: true) {
                    if tab.name.hasPrefix("add-") {
                        PermissionRuleFormView(onClose: { closeTab(tab.name) }) {
                            closeTab(tab.name)
                            Task { await load() }
                        }
                    } else if tab.name.hasPrefix("edit-") {
                        let id = Int(tab.name.replacingOccurrences(of: "edit-", with: "")) ?? 0
                        if let rule = rows.first(where: { $0.id == id }) {
                            PermissionRuleFormView(rule: rule, onClose: { closeTab(tab.name) }) {
                                closeTab(tab.name)
                                Task { await load() }
                            }
                        }
                    }
                }
            }
        }
    }

    private func closeTab(_ name: String) {
        tabs.removeAll { $0.name == name }
        if active == name { active = "list" }
    }

    private var selectedIndexes: Set<Int> {
        Set(rows.enumerated().compactMap { selected.contains($0.element.id) ? $0.offset : nil })
    }

    private func onToggleRow(_ idx: Int) {
        let id = rows[idx].id
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let type = resourceType.trimmingCharacters(in: .whitespaces)
        rows = await store.permissionRuleList(resourceType: type)
        selected.removeAll()
    }

    private func doBatchDelete() async {
        do {
            try await store.permissionRuleDelete(ids: Array(selected))
            app.toastSuccess("删除成功")
            selected.removeAll()
        } catch {
            app.toast(error, fallback: "删除失败")
        }
        await load()
    }
}

// MARK: 规则表单

struct PermissionRuleFormView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    var rule: PermissionRule? = nil
    var onClose: () -> Void
    var onSuccess: () -> Void

    @State private var form = PermissionRule()
    @State private var permissionType: Int? = 1
    @State private var dataScope: Int? = 1
    @State private var loading = false

    private var isEdit: Bool { rule != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(isEdit ? "编辑数据权限规则" : "新增数据权限规则")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text)

                FormTextField(label: L("perm.ruleName"), required: true, placeholder: "请输入规则名称", text: $form.ruleName)
                FormTextField(label: L("perm.resourceType"), required: true, placeholder: "如 uralyt_user / biz_order", text: $form.resourceType)
                FormPickerField(label: L("perm.grantType"), required: true, placeholder: "请选择权限类型", value: $permissionType,
                                options: PermissionRule.permissionTypes.map { ($0.value, $0.label) })
                FormPickerField(label: L("perm.dataScope"), required: true, placeholder: "请选择数据范围", value: $dataScope,
                                options: PermissionRule.dataScopes.map { ($0.value, $0.label) })
                FormRadioRow(label: "状态", options: [(1, "启用"), (0, "停用")], value: $form.status)
                FormTextareaField(label: L("eum.remark"), placeholder: String(format: L("eum.placeholder.inputFormat"), L("eum.remark")), text: $form.remark)

                FormActions(loading: loading) {
                    onClose()
                } onConfirm: {
                    Task { await submit() }
                }
            }
            .padding(20)
        }
        .onAppear {
            if let rule {
                form = rule
                permissionType = rule.permissionType
                dataScope = rule.dataScope
            }
        }
    }

    private func submit() async {
        guard !form.ruleName.isEmpty else { app.toastError("规则名称不能为空"); return }
        guard !form.resourceType.isEmpty else { app.toastError("资源类型不能为空"); return }
        form.permissionType = permissionType ?? 1
        form.dataScope = dataScope ?? 1
        loading = true
        defer { loading = false }
        do {
            if isEdit {
                try await store.permissionRuleUpdate(form)
                app.toastSuccess("修改成功")
            } else {
                try await store.permissionRuleInsert(form)
                app.toastSuccess("新增成功")
            }
            onSuccess()
        } catch {
            app.toast(error, fallback: "提交失败")
        }
    }
}

// MARK: 规则绑定（授权 / 例外）

struct RuleBindingSheet: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    @Environment(\.dismiss) private var dismiss

    let rule: PermissionRule
    let kind: DataPermissionView.BindingTarget.Kind

    @State private var grants: [PermissionGrant] = []
    @State private var exceptions: [PermissionException] = []
    @State private var loading = false
    @State private var showAdd = false

    // 新增表单
    @State private var userId: Int?
    @State private var roleId: Int?
    @State private var deptId: Int?
    @State private var exceptionType: Int? = 1

    private var isGrant: Bool { kind == .grant }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerBar
                if loading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if rowIDs.isEmpty {
                    Spacer()
                    Text(isGrant ? "暂无授权记录" : "暂无例外记录")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textSecondary)
                    Spacer()
                } else {
                    List {
                        ForEach(rowIDs, id: \.self) { rowID in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(primaryText(rowID))
                                        .font(.system(size: 13, weight: .medium))
                                    Text(secondaryText(rowID))
                                        .font(.system(size: 11))
                                        .foregroundColor(Theme.textSecondary)
                                }
                                Spacer()
                                if !isGrant, let e = exceptions.first(where: { $0.id == rowID }) {
                                    StatusTag(text: e.exceptionTypeText.split(separator: "（").first.map(String.init) ?? "例外",
                                              kind: e.exceptionType == 1 ? .success : .danger)
                                }
                                WireButton(title: L("button.delete"), icon: "delete", variant: .linkDanger, small: true) {
                                    Task { await remove(rowID) }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(isGrant ? "规则授权 - \(rule.ruleName)" : "规则例外 - \(rule.ruleName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("新增") { showAdd = true }.font(.system(size: 13, weight: .semibold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }.font(.system(size: 13))
                }
            }
            .sheet(isPresented: $showAdd) { addForm }
            .task { await reload() }
        }
        .presentationDetents([.medium, .large])
    }

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(isGrant ? "数据权限授权" : "数据权限例外")
                .font(.system(size: 15, weight: .semibold))
            Text("规则：\(rule.ruleName) ｜ 资源类型：\(rule.resourceType.isEmpty ? "-" : rule.resourceType)")
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.pageBG)
    }

    private var rowIDs: [Int] {
        isGrant ? grants.map(\.id) : exceptions.map(\.id)
    }

    private func primaryText(_ rowID: Int) -> String {
        guard let wrapped = wrappedItem(rowID) else { return "-" }
        return "用户：\(store.userName(wrapped.userId)) ｜ 角色：\(store.roleNames(wrapped.roleId.map { [$0] } ?? []))"
    }

    private func secondaryText(_ rowID: Int) -> String {
        guard let wrapped = wrappedItem(rowID) else { return "-" }
        return "部门：\(store.deptName(wrapped.deptId)) ｜ 创建时间：\(wrapped.createTime)"
    }

    private func wrappedItem(_ id: Int) -> (userId: Int?, roleId: Int?, deptId: Int?, createTime: String)? {
        if isGrant, let g = grants.first(where: { $0.id == id }) {
            return (g.userId, g.roleId, g.deptId, g.createTime)
        }
        if !isGrant, let e = exceptions.first(where: { $0.id == id }) {
            return (e.userId, e.roleId, e.deptId, e.createTime)
        }
        return nil
    }

    private var addForm: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    FormPickerField(label: L("eum.user"), placeholder: "可选", value: $userId,
                                    options: store.allUsers.map { ($0.id, $0.displayLabel) })
                    FormPickerField(label: L("eum.role"), placeholder: "可选", value: $roleId,
                                    options: store.roles.map { ($0.id, $0.roleName) })
                    FormPickerField(label: L("eum.dept"), placeholder: "可选", value: $deptId,
                                    options: store.depts.flatMap { $0.flattened() }.map { ($0.id, $0.deptName) })
                    if !isGrant {
                        FormRadioRow(label: "例外类型", options: [(1, "白名单放通"), (2, "黑名单拦截")], value: Binding(
                            get: { exceptionType ?? 1 },
                            set: { exceptionType = $0 }
                        ))
                    }
                    FormActions(confirmTitle: "提交") {
                        showAdd = false
                    } onConfirm: {
                        Task { await add(); showAdd = false }
                    }
                }
                .padding(20)
            }
            .navigationTitle(isGrant ? "新增授权" : "新增例外")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        if isGrant {
            grants = await store.permissionGrantList(ruleId: rule.id)
        } else {
            exceptions = await store.permissionExceptionList(ruleId: rule.id)
        }
    }

    private func add() async {
        guard userId != nil || roleId != nil || deptId != nil else {
            app.toastWarning("请至少选择用户 / 角色 / 部门之一")
            return
        }
        do {
            if isGrant {
                try await store.permissionGrantInsert(ruleId: rule.id, userId: userId, roleId: roleId, deptId: deptId)
            } else {
                try await store.permissionExceptionInsert(ruleId: rule.id, userId: userId, roleId: roleId,
                                                          deptId: deptId, exceptionType: exceptionType ?? 1)
            }
            app.toastSuccess(isGrant ? "授权成功" : "例外已添加")
            userId = nil; roleId = nil; deptId = nil; exceptionType = 1
            await reload()
        } catch {
            app.toast(error, fallback: "提交失败")
        }
    }

    private func remove(_ id: Int) async {
        do {
            if isGrant {
                try await store.permissionGrantDelete(ids: [id])
            } else {
                try await store.permissionExceptionDelete(ids: [id])
            }
            app.toastSuccess("删除成功")
            await reload()
        } catch {
            app.toast(error, fallback: "删除失败")
        }
    }
}

// MARK: - 审计日志（数据访问 / 权限变更）

struct AuditLogView: View {
    enum LogKind: String, CaseIterable, Identifiable {
        case access, permission
        var id: String { rawValue }
        var title: String { self == .access ? "数据访问日志" : "权限变更日志" }
    }

    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var kind: LogKind = .access
    @State private var userIdText = ""
    @State private var resourceType = ""
    @State private var page = 1
    @State private var pageSize = 10
    @State private var total = 0
    @State private var hasMore = false
    @State private var accessRows: [AccessLog] = []
    @State private var permissionRows: [PermissionChangeLog] = []
    @State private var loading = false

    private var isCompact: Bool { hSize == .compact }

    private var accessColumns: [TableCol] {
        [
            .init(L("eum.index"), 60, align: .center),
            .init(L("audit.user"), 150),
            .init(L("perm.resourceType"), 150),
            .init(L("perm.resourceId"), 100, align: .center),
            .init(L("audit.action"), 120),
            .init(L("audit.result"), 80, align: .center),
            .init(L("audit.ip"), 150),
            .init(L("audit.time"), 170),
        ]
    }

    private var permissionColumns: [TableCol] {
        [
            .init(L("eum.index"), 60, align: .center),
            .init(L("audit.user"), 150),
            .init(L("perm.targetUser"), 150),
            .init(L("perm.targetRole"), 150),
            .init(L("audit.changeType"), 120, align: .center),
            .init(L("perm.resourceType"), 120),
            .init(L("audit.oldValue"), 130),
            .init(L("audit.newValue"), 130),
            .init(L("audit.changeTime"), 170),
        ]
    }

    var body: some View {
        PageLayout(header: headerSection, scrolls: !isCompact) {
            if isCompact {
                mobileList
            } else {
                WireCard(fullHeight: true) {
                    VStack(spacing: 0) {
                    if kind == .access {
                        WireTable(columns: accessColumns, rowCount: accessRows.count, rowAction: { idx in accessRow(idx) })
                    } else {
                        WireTable(columns: permissionColumns, rowCount: permissionRows.count, rowAction: { idx in permissionRow(idx) })
                    }
                        PaginationBar(total: total, page: $page, pageSize: $pageSize) {
                            Task { await load() }
                        }
                    }
                }
            }
        }
        .overlay { TableLoadingOverlay(loading: loading) }
        .task { await load() }
    }

    /// 手机端：日志以卡片时间线呈现
    private var mobileList: some View {
        MobileCardList(
            cards: kind == .access ? accessRows.map(mobileCard) : permissionRows.map(mobileCard),
            total: total,
            selection: .constant([]),
            onLoadMore: hasMore ? { await loadMore() } : nil,
            hasMore: hasMore
        )
    }

    private func mobileCard(for log: AccessLog) -> MobileCardModel {
        MobileCardModel(
            id: log.id,
            title: store.userName(log.userId),
            subtitle: "\(log.resourceType.isEmpty ? "-" : log.resourceType)\(log.resourceId.map { " · ID \($0)" } ?? "")",
            initials: log.action.isEmpty ? "访" : String(log.action.prefix(1)).uppercased(),
            showBadge: true,
            badgeText: log.result == 1 ? "成功" : "失败",
            badgeKind: log.result == 1 ? .success : .danger,
            fields: [
                .init(label: L("audit.action"), value: log.action.isEmpty ? "-" : log.action),
                .init(label: L("audit.ip"), value: log.ipAddress.isEmpty ? "-" : log.ipAddress),
                .init(label: L("audit.time"), value: String(log.createTime.prefix(19))),
            ],
            actions: [],
            selectable: false
        )
    }

    private func mobileCard(for log: PermissionChangeLog) -> MobileCardModel {
        MobileCardModel(
            id: log.id,
            title: store.userName(log.userId),
            subtitle: "资源：\(log.resourceType.isEmpty ? "-" : log.resourceType)\(log.resourceId.map { " · ID \($0)" } ?? "")",
            initials: String(log.changeType.prefix(1)).uppercased(),
            showBadge: true,
            badgeText: log.changeType.isEmpty ? "-" : log.changeType,
            badgeKind: log.changeKind,
            fields: [
                .init(label: L("perm.targetUser"), value: log.targetUserId.map { store.userName($0) } ?? "-"),
                .init(label: L("perm.targetRole"), value: log.targetRoleId.map { store.roleNames([$0]) } ?? "-"),
                .init(label: L("audit.oldToNew"), value: "\(log.oldValue.isEmpty ? "-" : log.oldValue) → \(log.newValue.isEmpty ? "-" : log.newValue)"),
                .init(label: L("audit.changeTime"), value: String(log.createTime.prefix(19))),
            ],
            actions: [],
            selectable: false
        )
    }

    private func loadMore() async {
        guard !loading, hasMore else { return }
        page += 1
        await load(append: true)
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            QueryForm {
                QueryField(label: L("user.userId"), text: $userIdText)
                if kind == .access {
                    QueryField(label: L("perm.resourceType"), text: $resourceType)
                }
                Picker("", selection: $kind) {
                    ForEach(LogKind.allCases) { k in Text(k.title).tag(k) }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            } onSearch: {
                page = 1
                Task { await load() }
            } onReset: {
                userIdText = ""; resourceType = ""
                page = 1
                Task { await load() }
            }
        }
    }

    private func accessRow(_ idx: Int) -> some View {
        let log = accessRows[idx]
        return HStack(spacing: 0) {
            TableCell(text: "\(idx + 1 + (page - 1) * pageSize)", width: 60, align: .center, color: Theme.textSecondary)
            TableCell(text: store.userName(log.userId), width: 150)
            TableCell(text: log.resourceType.isEmpty ? "-" : log.resourceType, width: 150)
            TableCell(text: log.resourceId.map(String.init) ?? "-", width: 100, align: .center, mono: true)
            TableCell(text: log.action.isEmpty ? "-" : log.action, width: 120)
            HStack {
                StatusTag(text: log.result == 1 ? "成功" : "失败", kind: log.result == 1 ? .success : .danger)
            }
            .frame(width: 80, alignment: .center)
            TableCell(text: log.ipAddress.isEmpty ? "-" : log.ipAddress, width: 150, mono: true, color: Theme.textSecondary)
            TableCell(text: log.createTime, width: 170, color: Theme.textSecondary)
        }
    }

    private func permissionRow(_ idx: Int) -> some View {
        let log = permissionRows[idx]
        return HStack(spacing: 0) {
            TableCell(text: "\(idx + 1 + (page - 1) * pageSize)", width: 60, align: .center, color: Theme.textSecondary)
            TableCell(text: store.userName(log.userId), width: 150)
            TableCell(text: log.targetUserId.map { store.userName($0) } ?? "-", width: 150)
            TableCell(text: log.targetRoleId.map { store.roleNames([$0]) } ?? "-", width: 150)
            HStack { StatusTag(text: log.changeType.isEmpty ? "-" : log.changeType, kind: log.changeKind) }
                .frame(width: 120, alignment: .center)
            TableCell(text: log.resourceType.isEmpty ? "-" : log.resourceType, width: 120)
            TableCell(text: log.oldValue.isEmpty ? "-" : log.oldValue, width: 130, color: Theme.textSecondary)
            TableCell(text: log.newValue.isEmpty ? "-" : log.newValue, width: 130, color: Theme.textSecondary)
            TableCell(text: log.createTime, width: 170, color: Theme.textSecondary)
        }
    }

    private func load(append: Bool = false) async {
        loading = true
        defer { loading = false }
        let uid = Int(userIdText.trimmingCharacters(in: .whitespaces))
        do {
            if kind == .access {
                let r = try await store.accessLogPage(page: page, size: pageSize,
                                                      userId: uid, resourceType: resourceType, result: nil)
                accessRows = append ? accessRows + r.content : r.content
                total = r.total
            } else {
                let r = try await store.permissionLogPage(page: page, size: pageSize, userId: uid, changeType: "")
                permissionRows = append ? permissionRows + r.content : r.content
                total = r.total
            }
            hasMore = page * pageSize < total
        } catch {
            if append { page -= 1 }
            app.toast(error, fallback: "加载失败")
        }
    }
}
