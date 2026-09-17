import SwiftUI

// MARK: - 用户管理

struct EumUserView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    @Environment(\.horizontalSizeClass) private var hSize

    // 数据状态收敛到 ViewModel（MVVM：View 只渲染，业务走注入的 UserServiceProtocol）
    @State private var viewModel: EumUserViewModel
    // 动态页签（页面内导航状态，留在 View）
    @State private var tabs: [DynTab] = []
    @State private var active = "list"

    // 弹窗
    @State private var showBatchDelete = false
    @State private var showResetPwd = false
    @State private var resetPwdText = ""
    @State private var resetPwdError = ""
    /// 单用户重置密码（POST /eum_rbac_user/password）
    @State private var pwdTarget: SysUser?
    @State private var singlePwdText = ""
    @State private var singlePwdError = ""
    // Mobile
    @State private var showFilter = false
    @State private var mobileForm: MobileTarget?

    init(service: UserServiceProtocol = AppEnvironment.shared.users) {
        _viewModel = State(initialValue: EumUserViewModel(service: service))
    }

    /// 手机端表单 / 详情弹层目标
    enum MobileTarget: Identifiable {
        case add, detail(Int), edit(Int)
        var id: String {
            switch self {
            case .add: return "add"
            case .detail(let id): return "detail-\(id)"
            case .edit(let id): return "edit-\(id)"
            }
        }
        var title: String {
            switch self {
            case .add: return "新增用户"
            case .detail: return "用户详情"
            case .edit: return "编辑用户"
            }
        }
    }

    private var isCompact: Bool { hSize == .compact }

    private var columns: [TableCol] {
        [
            .init(L("eum.index"), 60, align: .center),
            .init(L("eum.user.read.username")),
            .init(L("eum.user.read.nickName")),
            .init(L("eum.user.read.phone"), 140),
            .init(L("eum.user.read.email"), 170),
            .init(L("eum.status"), 70, align: .center),
            .init(L("eum.operation"), 190, align: .center),
        ]
    }

    var body: some View {
        PageLayout(header: headerSection, scrolls: !isCompact) {
            if active == "list" {
                listSection
            } else {
                formAndDetailSections
            }
        }
        .overlay { TableLoadingOverlay(loading: viewModel.loading) }
        .task { await reload() }
    }

    // MARK: 头部（搜索 + 页签；手机端收纳为搜索框 + 筛选）

    private var headerSection: some View {
        VStack(spacing: 8) {
            if isCompact {
                MobileSearchBar(text: $viewModel.username,
                                placeholder: L("user.searchPlaceholder"),
                                filterCount: viewModel.filterCount,
                                onFilter: { showFilter = true },
                                onSubmit: { viewModel.page = 1; Task { await reload() } })
                FilterChipsBar(chips: filterChips, onClearAll: {
                    viewModel.resetFilters()
                    viewModel.page = 1
                    Task { await reload() }
                })
            } else {
                QueryForm {
                    QueryField(label: L("eum.user.read.username"), text: $viewModel.username)
                    QueryField(label: L("eum.user.read.phone"), text: $viewModel.phone)
                    QueryPickerField(label: L("eum.status"), value: $viewModel.status, options: DictOption.eumStatus)
                } onSearch: {
                    viewModel.page = 1
                    Task { await reload() }
                } onReset: {
                    viewModel.resetFilters()
                    viewModel.page = 1
                    Task { await reload() }
                }
                DynTabBar(tabs: $tabs, active: $active, fixedTitle: L("list.users"))
            }
        }
    }

    private var filterChips: [MobileFilterChip] {
        var chips: [MobileFilterChip] = []
        if !viewModel.phone.isEmpty {
            chips.append(.init(id: "phone", label: "手机号：\(viewModel.phone)", onRemove: {
                viewModel.phone = ""
                viewModel.page = 1
                Task { await reload() }
            }))
        }
        if let status = viewModel.status {
            chips.append(.init(id: "status", label: "状态：\(DictOption.eumStatus.first { $0.value == status }?.label ?? "\(status)")", onRemove: {
                viewModel.status = nil
                viewModel.page = 1
                Task { await reload() }
            }))
        }
        return chips
    }

    // MARK: 列表

    private var listSection: some View {
        Group {
            if isCompact {
                mobileList
            } else {
                desktopList
            }
        }
        .confirmationDialog(String(format: L("common.confirmDelete"), viewModel.selected.count), isPresented: $showBatchDelete, titleVisibility: .visible) {
            Button(L("button.delete"), role: .destructive) { Task { await doBatchDelete() } }
            Button(L("button.cancel"), role: .cancel) {}
        }
        .alert(L("button.batchResetPwd"), isPresented: $showResetPwd) {
            TextField(L("user.newPassword"), text: $resetPwdText)
            Button(L("button.confirm")) { Task { await doResetPwd() } }
            Button(L("button.cancel"), role: .cancel) { resetPwdError = "" }
        } message: {
            Text(resetPwdError.isEmpty ? String(format: L("user.batchPwdMessage"), viewModel.selected.count) : resetPwdError)
        }
        .alert(String(format: L("user.resetPwdFor"), pwdTarget?.username ?? ""), isPresented: Binding(
            get: { pwdTarget != nil },
            set: { if !$0 { pwdTarget = nil } }
        )) {
            TextField(L("user.newPassword"), text: $singlePwdText)
            Button(L("button.confirm")) { Task { await doSingleReset() } }
            Button(L("button.cancel"), role: .cancel) { pwdTarget = nil }
        } message: {
            Text(singlePwdError.isEmpty ? L("user.pwdRule") : singlePwdError)
        }
        .sheet(isPresented: $showFilter) { filterSheet }
        .sheet(item: $mobileForm) { target in
            MobileSheetContainer(title: target.title) {
                switch target {
                case .add:
                    UserFormView(onClose: { mobileForm = nil }) {
                        mobileForm = nil
                        Task { await reload() }
                    }
                case .edit(let id):
                    if let user = viewModel.rows.first(where: { $0.id == id }) {
                        UserFormView(user: user, onClose: { mobileForm = nil }) {
                            mobileForm = nil
                            Task { await reload() }
                        }
                    }
                case .detail(let id):
                    if let user = viewModel.rows.first(where: { $0.id == id }) {
                        UserDetailView(user: user, onClose: { mobileForm = nil })
                    }
                }
            }
        }
    }

    private var desktopList: some View {
        WireCard(fullHeight: true) {
            VStack(spacing: 0) {
                toolbar
                WireTable(columns: columns, rowCount: viewModel.rows.count, selectable: true, selection: selectedIndexes) { idx in
                    onToggleRow(idx)
                } rowAction: { idx in
                    row(idx)
                }
                PaginationBar(total: viewModel.total, page: $viewModel.page, pageSize: $viewModel.pageSize) {
                    Task { await reload() }
                }
            }
        }
    }

    private var mobileList: some View {
        ZStack(alignment: .bottomTrailing) {
            MobileCardList(
                cards: viewModel.rows.map(mobileCard),
                total: viewModel.total,
                selection: $viewModel.selected,
                batchActions: [
                    .init(title: L("button.batchDelete"), role: .danger) { showBatchDelete = true },
                    .init(title: L("button.batchResetPwd")) {
                        resetPwdText = ""; resetPwdError = ""
                        showResetPwd = true
                    },
                ],
                onLoadMore: viewModel.hasMore ? { await loadMore() } : nil,
                hasMore: viewModel.hasMore
            )
            if viewModel.selected.isEmpty {
                MobileFAB { mobileForm = .add }
                    .padding(.trailing, 16)
                    .padding(.bottom, 18)
            }
        }
    }

    /// 一行数据 → 一张移动端卡片
    private func mobileCard(for user: SysUser) -> MobileCardModel {
        MobileCardModel(
            id: user.id,
            title: user.nickName.isEmpty ? user.username : user.nickName,
            subtitle: user.deptId == nil ? user.username : "\(user.username) · \(store.deptName(user.deptId))",
            showBadge: true,
            badgeText: user.status == 1 ? L("eum.status.enable") : L("eum.status.disable"),
            badgeKind: user.status == 1 ? .success : .danger,
            fields: [
                .init(label: L("eum.user.read.phone"), value: user.phone),
                .init(label: L("user.dept"), value: store.deptName(user.deptId)),
                .init(label: L("eum.user.read.email"), value: user.email),
                .init(label: L("eum.role"), value: store.roleNames(user.roleIds)),
            ],
            actions: [
                .init(title: L("button.detail")) { mobileForm = .detail(user.id) },
                .init(title: L("button.edit")) { mobileForm = .edit(user.id) },
                .init(title: L("button.resetPwd")) {
                    singlePwdText = ""; singlePwdError = ""
                    pwdTarget = user
                },
            ]
        )
    }

    /// 手机端筛选弹层（查询条件收口）
    private var filterSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L("eum.status"))
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                        HStack(spacing: 8) {
                            ForEach(DictOption.eumStatus) { opt in
                                Button {
                                    viewModel.status = viewModel.status == opt.value ? nil : opt.value
                                } label: {
                                    Text(opt.label)
                                        .font(.system(size: 13))
                                        .foregroundColor(viewModel.status == opt.value ? .white : Theme.text)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .background(viewModel.status == opt.value ? Theme.primary : Theme.panelBG)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(viewModel.status == opt.value ? Theme.primary : Theme.border, lineWidth: 1)
                                        )
                                        .clipShape(RoundedCorner(radius: 8))
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("eum.user.read.phone"))
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                        TextField(String(format: L("eum.placeholder.inputFormat"), L("eum.user.read.phone")), text: $viewModel.phone)
                            .font(.system(size: 13))
                            .keyboardType(.phonePad)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(Theme.panelBG)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                    }
                    HStack(spacing: 10) {
                        WireButton(title: L("button.reset"), variant: .defaultPlain) {
                            viewModel.resetFilters()
                        }
                        WireButton(title: L("button.confirm"), variant: .primary) {
                            showFilter = false
                            viewModel.page = 1
                            Task { await reload() }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 6)
                }
                .padding(16)
            }
            .navigationTitle(L("button.filter"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            WireButton(title: L("button.add"), icon: "add-circle", variant: .primary) {
                active = tabs.open(name: "add-\(Int(Date().timeIntervalSince1970))", title: L("button.add"))
            }
            WireButton(title: L("button.batchDelete"), icon: "delete", variant: .danger, disabled: viewModel.selected.isEmpty) {
                showBatchDelete = true
            }
            WireButton(title: L("button.batchResetPwd"), icon: "password-reset", variant: .ghost, disabled: viewModel.selected.isEmpty) {
                resetPwdText = ""; resetPwdError = ""
                showResetPwd = true
            }
            Spacer()
        }
        .padding(12)
    }

    private func row(_ idx: Int) -> some View {
        let user = viewModel.rows[idx]
        return HStack(spacing: 0) {
            TableCell(text: "\(idx + 1 + (viewModel.page - 1) * viewModel.pageSize)", width: 60, align: .center, color: Theme.textSecondary)
            TableCell(text: user.username)
            TableCell(text: user.nickName)
            TableCell(text: user.phone, width: 140)
            TableCell(text: user.email, width: 170)
            HStack {
                StatusSwitch(isOn: user.status == 1) { newValue in
                    Task { await toggleStatus(user, newValue) }
                }
            }
            .frame(width: 70, alignment: .center)
            HStack(spacing: 10) {
                WireButton(title: L("button.detail"), icon: "book", variant: .linkPrimary, small: true) {
                    active = tabs.open(name: "detail-\(user.id)", title: String(format: L("tab.detail"), user.username))
                }
                WireButton(title: L("button.edit"), icon: "pencil", variant: .linkPrimary, small: true) {
                    active = tabs.open(name: "edit-\(user.id)", title: String(format: L("tab.edit"), user.username))
                }
                WireButton(title: L("button.resetPwd"), icon: "password-reset", variant: .linkPlain, small: true) {
                    singlePwdText = ""; singlePwdError = ""
                    pwdTarget = user
                }
            }
            .frame(width: 190, alignment: .center)
        }
    }

    // MARK: 表单 / 详情
    @ViewBuilder
    private var formAndDetailSections: some View {
        ForEach(tabs) { tab in
            if active == tab.name {
                WireCard(fullHeight: true) {
                    if tab.name.hasPrefix("add-") {
                        UserFormView(onClose: { closeTab(tab.name) }) {
                            closeTab(tab.name)
                            Task { await reload() }
                        }
                    } else if tab.name.hasPrefix("edit-") {
                        let id = Int(tab.name.replacingOccurrences(of: "edit-", with: "")) ?? 0
                        if let user = viewModel.rows.first(where: { $0.id == id }) {
                            UserFormView(user: user, onClose: { closeTab(tab.name) }) {
                                closeTab(tab.name)
                                Task { await reload() }
                            }
                        }
                    } else if tab.name.hasPrefix("detail-") {
                        let id = Int(tab.name.replacingOccurrences(of: "detail-", with: "")) ?? 0
                        if let user = viewModel.rows.first(where: { $0.id == id }) {
                            UserDetailView(user: user, onClose: { closeTab(tab.name) })
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

    // MARK: 数据
    private var selectedIndexes: Set<Int> {
        // 行索引集合（基于 page 内行）
        Set(viewModel.rows.enumerated().compactMap { viewModel.selected.contains($0.element.id) ? $0.offset : nil })
    }

    private func onToggleRow(_ idx: Int) {
        let id = viewModel.rows[idx].id
        if viewModel.selected.contains(id) {
            viewModel.selected.remove(id)
        } else {
            viewModel.selected.insert(id)
        }
    }

    private func reload() async {
        do { try await viewModel.load() }
        catch { app.toast(error, fallback: L("common.loadFailed")) }
    }

    /// 手机端：页脚触发加载下一页
    private func loadMore() async {
        do { try await viewModel.loadMore() }
        catch { app.toast(error, fallback: L("common.loadFailed")) }
    }

    private func toggleStatus(_ user: SysUser, _ on: Bool) async {
        do {
            try await viewModel.setStatus(user, on: on)
            app.toastSuccess(L("user.statusChanged"))
        } catch {
            app.toast(error, fallback: L("common.opFailed"))
        }
    }

    private func doBatchDelete() async {
        do {
            try await viewModel.batchDelete()
            app.toastSuccess(L("common.deleted"))
        } catch {
            app.toast(error, fallback: L("button.delete") + L("common.opFailed"))
        }
        await reload()
    }

    private func doResetPwd() async {
        guard resetPwdText.count >= 5, resetPwdText.count <= 20 else {
            resetPwdError = L("user.pwdLength")
            showResetPwd = true
            return
        }
        do {
            try await viewModel.resetPassword(for: Array(viewModel.selected), newPassword: resetPwdText)
            app.toastSuccess(String(format: L("user.batchResetDone"), resetPwdText))
            viewModel.clearSelection()
        } catch {
            app.toast(error, fallback: L("user.resetFailed"))
        }
    }

    /// 单用户重置密码（§4.23 POST /eum_rbac_user/password）
    private func doSingleReset() async {
        guard let target = pwdTarget else { return }
        guard singlePwdText.count >= 5, singlePwdText.count <= 20 else {
            singlePwdError = L("user.pwdLength")
            return
        }
        do {
            try await viewModel.resetPassword(id: target.id, newPassword: singlePwdText)
            app.toastSuccess(String(format: L("user.resetDone"), singlePwdText))
            pwdTarget = nil
        } catch {
            singlePwdError = (error as? APIClient.ApiError)?.message ?? "重置失败"
            app.toast(error, fallback: L("user.resetFailed"))
        }
    }
}

// MARK: - 用户表单

struct UserFormView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    /// 服务协议注入（真实 / Mock 由 AppEnvironment 装配）
    var service: UserServiceProtocol = AppEnvironment.shared.users
    var user: SysUser? = nil
    var onClose: () -> Void
    var onSuccess: () -> Void

    @State private var form = SysUser(id: 0, username: "", nickName: "", phone: "", email: "")
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var roleSelection: Set<Int> = []
    @State private var postSelection: Set<Int> = []
    @State private var showDeptPicker = false
    @State private var showRolePicker = false
    @State private var showPostPicker = false
    @State private var loading = false
    @State private var hydrated = false

    private var isEdit: Bool { user != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(isEdit ? L("user.editTitle") : L("user.addTitle"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text)

                FormTextField(label: L("eum.user.read.username"), required: true, placeholder: String(format: L("eum.placeholder.inputFormat"), L("eum.user.read.username")), text: $form.username)
                if !isEdit {
                    FormTextField(label: L("user.password"), required: true, placeholder: String(format: L("eum.placeholder.inputFormat"), L("user.password")), text: $password)
                    FormTextField(label: L("user.confirmPassword"), required: true, placeholder: L("auth.register.confirmPlaceholder"), text: $confirmPassword)
                }
                FormTextField(label: L("eum.user.read.nickName"), required: true, placeholder: String(format: L("eum.placeholder.inputFormat"), L("eum.user.read.nickName")), text: $form.nickName)
                FormTextField(label: L("eum.user.read.realName"), placeholder: String(format: L("eum.placeholder.inputFormat"), L("eum.user.read.realName")), text: $form.realName)
                FormTextField(label: L("eum.user.read.phone"), placeholder: String(format: L("eum.placeholder.inputFormat"), L("eum.user.read.phone")), text: $form.phone)
                FormTextField(label: L("eum.user.read.email"), placeholder: String(format: L("eum.placeholder.inputFormat"), L("eum.user.read.email")), text: $form.email)
                FormRadioRow(label: L("eum.user.read.gender"), options: [(1, L("common.male")), (0, L("common.female"))], value: $form.gender)

                // 上级部门
                HStack(spacing: 8) {
                    FormFieldLabel(text: L("user.dept"))
                    Button {
                        showDeptPicker = true
                    } label: {
                        HStack {
                            Text(form.deptId == nil ? String(format: L("eum.placeholder.selectFormat"), L("user.dept")) : store.deptName(form.deptId))
                                .font(.system(size: 13))
                                .foregroundColor(form.deptId == nil ? Theme.textTertiary : Theme.text)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.textTertiary)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(Theme.panelBG)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                multiSelectField(label: L("user.roles"), placeholder: String(format: L("eum.placeholder.selectFormat"), L("user.roles")),
                                 text: store.roleNames(Array(roleSelection)),
                                 show: $showRolePicker)
                multiSelectField(label: L("user.posts"), placeholder: String(format: L("eum.placeholder.selectFormat"), L("user.posts")),
                                 text: store.postNames(Array(postSelection)),
                                 show: $showPostPicker)

                FormRadioRow(label: L("eum.status"), options: [(1, L("eum.status.enable")), (0, L("eum.status.disable"))], value: $form.status)
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
            if let user {
                form = user
                roleSelection = Set(user.roleIds)
                postSelection = Set(user.postIds)
            }
        }
        /// §4.23 列表行不含角色/岗位关联，进入编辑时按 ID 拉取完整明细回填
        .task {
            guard let user, !hydrated else { return }
            hydrated = true
            if let detail = try? await service.detail(id: user.id) {
                form = detail
                roleSelection = Set(detail.roleIds)
                postSelection = Set(detail.postIds)
            }
        }
        .sheet(isPresented: $showDeptPicker) {
            DeptTreePicker(selected: Binding(
                get: { form.deptId.map { DeptPick(id: $0, name: "") } },
                set: { form.deptId = $0?.id }
            ))
        }
        .sheet(isPresented: $showRolePicker) {
            MultiCheckPicker(title: L("user.roles"), options: store.roles.map { ($0.id, $0.roleName) }, selection: $roleSelection)
        }
        .sheet(isPresented: $showPostPicker) {
            MultiCheckPicker(title: L("user.posts"), options: store.posts.map { ($0.id, $0.postName) }, selection: $postSelection)
        }
    }

    private func multiSelectField(label: String, placeholder: String, text: String, show: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            FormFieldLabel(text: label)
            Button {
                show.wrappedValue = true
            } label: {
                HStack {
                    Text(text.isEmpty || text == "无" ? placeholder : text)
                        .font(.system(size: 13))
                        .foregroundColor(text.isEmpty || text == "无" ? Theme.textTertiary : Theme.text)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(Theme.panelBG)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func submit() async {
        guard !form.username.isEmpty else { app.toastError(L("user.nameRequired")); return }
        guard !form.nickName.isEmpty else { app.toastError(L("user.nickRequired")); return }
        if !isEdit {
            guard password.count >= 5, password.count <= 20 else { app.toastError(L("user.pwdLength")); return }
            guard password == confirmPassword else { app.toastError(L("auth.message.passwordMismatch")); return }
        }
        form.roleIds = Array(roleSelection)
        form.postIds = Array(postSelection)
        loading = true
        defer { loading = false }
        do {
            if isEdit {
                try await service.update(form)
                app.toastSuccess(L("common.updated"))
            } else {
                try await service.insert(form, password: password)
                app.toastSuccess(L("common.added"))
            }
            onSuccess()
        } catch {
            app.toast(error, fallback: L("common.submitFailed"))
        }
    }
}

struct DeptPick: Identifiable, Hashable {
    let id: Int
    let name: String
}

// MARK: - 用户详情

struct UserDetailView: View {
    @EnvironmentObject var store: DataService
    var service: UserServiceProtocol = AppEnvironment.shared.users
    let user: SysUser
    var onClose: () -> Void

    @State private var detail: SysUser?

    private var model: SysUser { detail ?? user }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("用户详情")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text)

                DetailGrid(items: [
                    .init(label: L("eum.user.read.username"), value: model.username),
                    .init(label: L("eum.user.read.nickName"), value: model.nickName),
                    .init(label: L("eum.user.read.realName"), value: model.realName.isEmpty ? "-" : model.realName),
                    .init(label: L("eum.user.read.gender"), value: model.gender == 1 ? L("common.male") : L("common.female")),
                    .init(label: L("eum.user.read.phone"), value: model.phone),
                    .init(label: L("eum.user.read.email"), value: model.email),
                    .init(label: L("user.dept"), value: store.deptName(model.deptId)),
                    .init(label: L("eum.status"), value: Theme.statusText(model.status)),
                    .init(label: L("user.roles"), value: store.roleNames(model.roleIds), span2: true),
                    .init(label: L("user.posts"), value: store.postNames(model.postIds), span2: true),
                    .init(label: L("eum.remark"), value: model.remark.isEmpty ? "-" : model.remark, span2: true),
                    .init(label: L("eum.createBy"), value: model.createBy),
                    .init(label: L("eum.createTime"), value: model.createTime),
                ])

                HStack {
                    Spacer()
                    WireButton(title: L("button.close"), variant: .defaultPlain, action: onClose)
                }
            }
            .padding(20)
        }
        /// 按 ID 拉取完整明细（角色 / 岗位 / 部门关联）
        .task {
            if let fetched = try? await service.detail(id: user.id) {
                detail = fetched
            }
        }
    }
}

// MARK: - 通用多选弹窗

struct MultiCheckPicker: View {
    let title: String
    let options: [(Int, String)]
    @Binding var selection: Set<Int>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(options, id: \.0) { id, name in
                        Button {
                            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
                        } label: {
                            HStack {
                                Text(name).font(.system(size: 13)).foregroundColor(Theme.text)
                                Spacer()
                                Image(systemName: selection.contains(id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selection.contains(id) ? Theme.primary : Theme.textTertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                            .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderLight).frame(height: 1) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("button.cancel")) { dismiss() }.font(.system(size: 13))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("button.confirm")) { dismiss() }.font(.system(size: 13, weight: .semibold))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - 部门树选择弹窗

struct DeptTreePicker: View {
    @Binding var selected: DeptPick?
    @EnvironmentObject var store: DataService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    deptRow(name: L("user.noParent"), id: nil)
                    ForEach(store.depts) { dept in
                        deptNode(dept, depth: 0)
                    }
                }
            }
            .navigationTitle(L("user.dept"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("button.cancel")) { dismiss() }.font(.system(size: 13))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func deptRow(name: String, id: Int?) -> some View {
        let isSel = selected?.id == id
        return Button {
            selected = id.map { DeptPick(id: $0, name: name) }
            dismiss()
        } label: {
            HStack {
                Text(name)
                    .font(.system(size: 13, weight: isSel ? .semibold : .regular))
                    .foregroundColor(isSel ? Theme.primary : Theme.text)
                Spacer()
                if isSel {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.primary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSel ? Theme.borderLight : .clear)
        }
        .buttonStyle(.plain)
    }

    private func deptNode(_ dept: SysDept, depth: Int) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 0) {
                deptRow(name: dept.deptName, id: dept.id)
                    .padding(.leading, CGFloat(depth) * 18)
                ForEach(dept.children) { child in
                    deptNode(child, depth: depth + 1)
                }
            }
        )
    }
}
