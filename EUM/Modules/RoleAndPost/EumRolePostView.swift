import SwiftUI

// MARK: - 角色管理

struct EumRoleView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var roleName = ""
    @State private var roleKey = ""
    @State private var status: Int?
    @State private var page = 1
    @State private var pageSize = 10
    @State private var total = 0
    @State private var rows: [SysRole] = []
    @State private var loading = false
    @State private var hasMore = false
    @State private var selected: Set<Int> = []
    @State private var tabs: [DynTab] = []
    @State private var active = "list"
    @State private var showBatchDelete = false
    @State private var showFilter = false
    @State private var mobileForm: MobileTarget?

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
            case .add: return "新增角色"
            case .detail: return "角色详情"
            case .edit: return "编辑角色"
            }
        }
    }

    private var isCompact: Bool { hSize == .compact }

    private var columns: [TableCol] = [
        .init(L("eum.index"), 60, align: .center),
        .init(L("eum.role.read.roleName")),
        .init(L("eum.role.read.roleKey")),
        .init(L("eum.sort"), 80, align: .center),
        .init(L("eum.status"), 70, align: .center),
        .init(L("eum.operation"), 130, align: .center),
    ]

    var body: some View {
        PageLayout(header: headerSection, scrolls: !isCompact) {
            if active == "list" {
                listSection
            } else {
                tabSections
            }
        }
        .overlay { TableLoadingOverlay(loading: loading) }
        .task { await load() }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            if isCompact {
                MobileSearchBar(text: $roleName,
                                placeholder: String(format: L("common.searchFormat"), L("eum.role.read.roleName")),
                                filterCount: (roleKey.isEmpty ? 0 : 1) + (status == nil ? 0 : 1),
                                onFilter: { showFilter = true },
                                onSubmit: { page = 1; Task { await load() } })
                FilterChipsBar(chips: filterChips, onClearAll: {
                    roleKey = ""; status = nil
                    page = 1
                    Task { await load() }
                })
            } else {
                QueryForm {
                    QueryField(label: L("eum.role.read.roleName"), text: $roleName)
                    QueryField(label: L("eum.role.read.roleKey"), text: $roleKey)
                    QueryPickerField(label: L("eum.status"), value: $status, options: DictOption.eumStatus)
                } onSearch: {
                    page = 1
                    Task { await load() }
                } onReset: {
                    roleName = ""; roleKey = ""; status = nil
                    page = 1
                    Task { await load() }
                }
                DynTabBar(tabs: $tabs, active: $active, fixedTitle: L("list.roles"))
            }
        }
    }

    private var filterChips: [MobileFilterChip] {
        var chips: [MobileFilterChip] = []
        if !roleKey.isEmpty {
            chips.append(.init(id: "key", label: "权限字符：\(roleKey)", onRemove: {
                roleKey = ""
                page = 1
                Task { await load() }
            }))
        }
        if let status {
            chips.append(.init(id: "status", label: "状态：\(DictOption.eumStatus.first { $0.value == status }?.label ?? "\(status)")", onRemove: {
                self.status = nil
                page = 1
                Task { await load() }
            }))
        }
        return chips
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
        .sheet(isPresented: $showFilter) { filterSheet }
        .sheet(item: $mobileForm) { target in
            MobileSheetContainer(title: target.title) {
                switch target {
                case .add:
                    RoleFormView(onClose: { mobileForm = nil }) {
                        mobileForm = nil
                        Task { await load() }
                    }
                case .edit(let id):
                    if let role = rows.first(where: { $0.id == id }) {
                        RoleFormView(role: role, onClose: { mobileForm = nil }) {
                            mobileForm = nil
                            Task { await load() }
                        }
                    }
                case .detail(let id):
                    if let role = rows.first(where: { $0.id == id }) {
                        RoleDetailView(role: role, onClose: { mobileForm = nil })
                    }
                }
            }
        }
    }

    private var desktopList: some View {
        WireCard(fullHeight: true) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    WireButton(title: L("button.add"), icon: "add-circle", variant: .primary) {
                        active = tabs.open(name: "add-\(Int(Date().timeIntervalSince1970))", title: L("button.add"))
                    }
                    WireButton(title: L("button.batchDelete"), icon: "delete", variant: .danger, disabled: selected.isEmpty) {
                        showBatchDelete = true
                    }
                    Spacer()
                }
                .padding(12)

                WireTable(columns: columns, rowCount: rows.count, selectable: true, selection: selectedIndexes()) { idx in
                    let id = rows[idx].id
                    if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
                } rowAction: { idx in
                    row(idx)
                }

                PaginationBar(total: total, page: $page, pageSize: $pageSize) {
                    Task { await load() }
                }
            }
        }
    }

    private var mobileList: some View {
        ZStack(alignment: .bottomTrailing) {
            MobileCardList(
                cards: rows.map(mobileCard),
                total: total,
                selection: $selected,
                batchActions: [
                    .init(title: L("button.batchDelete"), role: .danger) { showBatchDelete = true },
                ],
                onLoadMore: hasMore ? { await loadMore() } : nil,
                hasMore: hasMore
            )
            if selected.isEmpty {
                MobileFAB { mobileForm = .add }
                    .padding(.trailing, 16)
                    .padding(.bottom, 18)
            }
        }
    }

    private func mobileCard(for role: SysRole) -> MobileCardModel {
        MobileCardModel(
            id: role.id,
            title: role.roleName,
            subtitle: role.roleKey,
            initials: String(role.roleName.prefix(1)),
            showBadge: true,
            badgeText: role.status == 1 ? L("eum.status.enable") : L("eum.status.disable"),
            badgeKind: role.status == 1 ? .success : .danger,
            fields: [
                .init(label: L("eum.sort"), value: "\(role.roleSort)"),
                .init(label: L("eum.role.read.menuPerms"), value: "\(role.menuIds.count) 项"),
                .init(label: L("eum.remark"), value: role.remark.isEmpty ? "-" : role.remark),
                .init(label: L("eum.createTime"), value: String(role.createTime.prefix(19))),
            ],
            actions: [
                .init(title: L("button.detail")) { mobileForm = .detail(role.id) },
                .init(title: L("button.edit")) { mobileForm = .edit(role.id) },
                .init(title: role.status == 1 ? L("eum.status.disable") : L("eum.status.enable")) {
                    Task { await toggleStatus(role, role.status != 1) }
                },
            ]
        )
    }

    /// 手机端筛选弹层
    private var filterSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("状态")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                        HStack(spacing: 8) {
                            ForEach(DictOption.eumStatus) { opt in
                                Button {
                                    status = status == opt.value ? nil : opt.value
                                } label: {
                                    Text(opt.label)
                                        .font(.system(size: 13))
                                        .foregroundColor(status == opt.value ? .white : Theme.text)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .background(status == opt.value ? Theme.primary : Theme.panelBG)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(status == opt.value ? Theme.primary : Theme.border, lineWidth: 1)
                                        )
                                        .clipShape(RoundedCorner(radius: 8))
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("权限字符")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                        TextField("请输入权限字符", text: $roleKey)
                            .font(.system(size: 13))
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(Theme.panelBG)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                    }
                    HStack(spacing: 10) {
                        WireButton(title: L("button.reset"), variant: .defaultPlain) {
                            roleKey = ""
                            status = nil
                        }
                        WireButton(title: L("button.confirm"), variant: .primary) {
                            showFilter = false
                            page = 1
                            Task { await load() }
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

    private func row(_ idx: Int) -> some View {
        let role = rows[idx]
        return HStack(spacing: 0) {
            TableCell(text: "\(idx + 1 + (page - 1) * pageSize)", width: 60, align: .center, color: Theme.textSecondary)
            TableCell(text: role.roleName)
            TableCell(text: role.roleKey)
            TableCell(text: "\(role.roleSort)", width: 80, align: .center)
            HStack {
                StatusSwitch(isOn: role.status == 1) { on in
                    Task { await toggleStatus(role, on) }
                }
            }
            .frame(width: 70, alignment: .center)
            HStack(spacing: 10) {
                WireButton(title: L("button.detail"), icon: "book", variant: .linkPrimary, small: true) {
                    active = tabs.open(name: "detail-\(role.id)", title: String(format: L("tab.detail"), role.roleName))
                }
                WireButton(title: L("button.edit"), icon: "pencil", variant: .linkPrimary, small: true) {
                    active = tabs.open(name: "edit-\(role.id)", title: String(format: L("tab.edit"), role.roleName))
                }
            }
            .frame(width: 130, alignment: .center)
        }
    }

    @ViewBuilder
    private var tabSections: some View {
        ForEach(tabs) { tab in
            if active == tab.name {
                WireCard(fullHeight: true) {
                    if tab.name.hasPrefix("add-") {
                        RoleFormView(onClose: { closeTab(tab.name) }) {
                            closeTab(tab.name)
                            Task { await load() }
                        }
                    } else if tab.name.hasPrefix("edit-") {
                        let id = Int(tab.name.replacingOccurrences(of: "edit-", with: "")) ?? 0
                        if let role = rows.first(where: { $0.id == id }) {
                            RoleFormView(role: role, onClose: { closeTab(tab.name) }) {
                                closeTab(tab.name)
                                Task { await load() }
                            }
                        }
                    } else if tab.name.hasPrefix("detail-") {
                        let id = Int(tab.name.replacingOccurrences(of: "detail-", with: "")) ?? 0
                        if let role = rows.first(where: { $0.id == id }) {
                            RoleDetailView(role: role, onClose: { closeTab(tab.name) })
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

    private func selectedIndexes() -> Set<Int> {
        Set(rows.enumerated().compactMap { selected.contains($0.element.id) ? $0.offset : nil })
    }

    private func load(append: Bool = false) async {
        loading = true
        defer { loading = false }
        do {
            let r = try await store.rolePage(page: page, size: pageSize, roleName: roleName, roleKey: roleKey, status: status)
            rows = append ? rows + r.content : r.content
            total = r.total
            hasMore = !r.content.isEmpty && rows.count < r.total
            if !append { selected.removeAll() }
        } catch {
            if append { page -= 1 }
            app.toastError("加载失败")
        }
    }

    private func loadMore() async {
        guard !loading, hasMore else { return }
        page += 1
        await load(append: true)
    }

    private func toggleStatus(_ role: SysRole, _ on: Bool) async {
        do {
            try await store.roleStatus(id: role.id, status: on ? 1 : 0)
            rows = rows.map { $0.id == role.id ? role : $0 }
            app.toastSuccess(L("user.statusChanged"))
        } catch {
            app.toast(error, fallback: "操作失败")
        }
    }

    private func doBatchDelete() async {
        do {
            try await store.roleDelete(ids: Array(selected))
            app.toastSuccess("删除成功")
        } catch {
            app.toast(error, fallback: "删除失败")
        }
        selected.removeAll()
        await load()
    }
}

// MARK: - 角色表单

struct RoleFormView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    var role: SysRole? = nil
    var onClose: () -> Void
    var onSuccess: () -> Void

    @State private var form = SysRole(id: 0, roleName: "", roleKey: "")
    @State private var menuChecked: Set<Int> = []
    @State private var loading = false

    private var isEdit: Bool { role != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(isEdit ? "编辑角色" : "新增角色")
                    .font(.system(size: 16, weight: .semibold))

                FormTextField(label: L("eum.role.read.roleName"), required: true, placeholder: "请输入角色名称", text: $form.roleName)
                FormTextField(label: L("eum.role.read.roleKey"), required: true, placeholder: "请输入权限字符", text: $form.roleKey)
                FormNumberField(label: "显示排序", required: true, value: $form.roleSort)
                FormRadioRow(label: "状态", options: [(1, "启用"), (0, "停用")], value: $form.status)

                VStack(alignment: .leading, spacing: 6) {
                    Text("菜单权限")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text)
                    MenuCheckTree(menus: store.menus, checked: $menuChecked)
                }

                FormTextareaField(label: L("eum.remark"), placeholder: String(format: L("eum.placeholder.inputFormat"), L("eum.remark")), text: $form.remark)

                FormActions(loading: loading) {
                    onClose()
                } onConfirm: {
                    Task { await submit() }
                }
            }
            .padding(20)
        }
        .task {
            if let role {
                form = role
                menuChecked = Set(role.menuIds)
                // 详情接口补全菜单权限 ids
                if let detail = try? await store.roleDetail(id: role.id), !detail.menuIds.isEmpty {
                    menuChecked = Set(detail.menuIds)
                }
            }
        }
    }

    private func submit() async {
        guard !form.roleName.isEmpty else { app.toastError("角色名称不能为空"); return }
        guard !form.roleKey.isEmpty else { app.toastError("权限字符不能为空"); return }
        // 勾选 + 半选父级一并提交（对齐 web getCheckedKeys + getHalfCheckedKeys）
        form.menuIds = Array(menuCheckedWithParents)
        loading = true
        defer { loading = false }
        do {
            if isEdit {
                try await store.roleUpdate(form)
                app.toastSuccess("修改成功")
            } else {
                try await store.roleInsert(form)
                app.toastSuccess("新增成功")
            }
            onSuccess()
        } catch {
            app.toast(error, fallback: "提交失败")
        }
    }

    /// 补全被勾选节点的父级链（半选语义）
    private var menuCheckedWithParents: Set<Int> {
        var result = menuChecked
        func walk(_ list: [SysMenu], parents: [Int]) {
            for m in list {
                let chain = parents + [m.id]
                if menuChecked.contains(m.id) || chain.dropLast().contains(where: { menuChecked.contains($0) }) {
                    if menuChecked.contains(m.id) {
                        chain.forEach { result.insert($0) }
                    }
                }
                walk(m.children, parents: chain)
            }
        }
        walk(store.menus, parents: [])
        return result
    }
}

// MARK: - 角色详情

struct RoleDetailView: View {
    @EnvironmentObject var store: DataService
    let role: SysRole
    var onClose: () -> Void
    @State private var checked: Set<Int> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("角色详情")
                    .font(.system(size: 16, weight: .semibold))

                DetailGrid(items: [
                    .init(label: L("eum.role.read.roleName"), value: role.roleName),
                    .init(label: L("eum.role.read.roleKey"), value: role.roleKey),
                    .init(label: L("eum.sort"), value: "\(role.roleSort)"),
                    .init(label: L("eum.status"), value: Theme.statusText(role.status)),
                    .init(label: L("eum.createBy"), value: role.createBy),
                    .init(label: L("eum.createTime"), value: role.createTime),
                    .init(label: L("eum.remark"), value: role.remark.isEmpty ? "-" : role.remark, span2: true),
                ])

                VStack(alignment: .leading, spacing: 6) {
                    Text("菜单权限")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.text)
                    MenuCheckTree(menus: store.menus, checked: $checked)
                        .frame(maxHeight: 300, alignment: .top)
                        .clipped()
                }

                HStack {
                    Spacer()
                    WireButton(title: L("button.close"), variant: .defaultPlain, action: onClose)
                }
            }
            .padding(20)
        }
        .task {
            if let detail = try? await store.roleDetail(id: role.id), !detail.menuIds.isEmpty {
                checked = Set(detail.menuIds)
            } else if !role.menuIds.isEmpty {
                checked = Set(role.menuIds)
            } else {
                // detail / 列表均未带回菜单，回退到「角色-菜单」关联表
                let ids = await store.roleMenuIds(roleId: role.id)
                if !ids.isEmpty { checked = Set(ids) }
            }
        }
    }
}

// MARK: - 岗位管理

struct EumPostView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var postCode = ""
    @State private var postName = ""
    @State private var status: Int?
    @State private var page = 1
    @State private var pageSize = 10
    @State private var total = 0
    @State private var rows: [SysPost] = []
    @State private var loading = false
    @State private var hasMore = false
    @State private var selected: Set<Int> = []
    @State private var tabs: [DynTab] = []
    @State private var showFilter = false
    @State private var mobileForm: MobileTarget?

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
            case .add: return "新增岗位"
            case .detail: return "岗位详情"
            case .edit: return "编辑岗位"
            }
        }
    }

    private var isCompact: Bool { hSize == .compact }

    @State private var active = "list"
    @State private var showBatchDelete = false

    private var columns: [TableCol] = [
        .init(L("eum.index"), 60, align: .center),
        .init(L("eum.post.read.postCode")),
        .init(L("eum.post.read.postName")),
        .init(L("eum.sort"), 80, align: .center),
        .init(L("eum.status"), 70, align: .center),
        .init(L("eum.operation"), 130, align: .center),
    ]

    var body: some View {
        PageLayout(header: headerSection, scrolls: !isCompact) {
            if active == "list" {
                listSection
            } else {
                tabSections
            }
        }
        .overlay { TableLoadingOverlay(loading: loading) }
        .task { await load() }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            if isCompact {
                MobileSearchBar(text: $postName,
                                placeholder: String(format: L("common.searchFormat"), L("eum.post.read.postName")),
                                filterCount: (postCode.isEmpty ? 0 : 1) + (status == nil ? 0 : 1),
                                onFilter: { showFilter = true },
                                onSubmit: { page = 1; Task { await load() } })
                FilterChipsBar(chips: filterChips, onClearAll: {
                    postCode = ""; status = nil
                    page = 1
                    Task { await load() }
                })
            } else {
                QueryForm {
                    QueryField(label: L("eum.post.read.postCode"), text: $postCode)
                    QueryField(label: L("eum.post.read.postName"), text: $postName)
                    QueryPickerField(label: L("eum.status"), value: $status, options: DictOption.eumStatus)
                } onSearch: {
                    page = 1
                    Task { await load() }
                } onReset: {
                    postCode = ""; postName = ""; status = nil
                    page = 1
                    Task { await load() }
                }
                DynTabBar(tabs: $tabs, active: $active, fixedTitle: L("list.posts"))
            }
        }
    }

    private var filterChips: [MobileFilterChip] {
        var chips: [MobileFilterChip] = []
        if !postCode.isEmpty {
            chips.append(.init(id: "code", label: "编码：\(postCode)", onRemove: {
                postCode = ""
                page = 1
                Task { await load() }
            }))
        }
        if let status {
            chips.append(.init(id: "status", label: "状态：\(DictOption.eumStatus.first { $0.value == status }?.label ?? "\(status)")", onRemove: {
                self.status = nil
                page = 1
                Task { await load() }
            }))
        }
        return chips
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
        .sheet(isPresented: $showFilter) { filterSheet }
        .sheet(item: $mobileForm) { target in
            MobileSheetContainer(title: target.title) {
                switch target {
                case .add:
                    PostFormView(onClose: { mobileForm = nil }) {
                        mobileForm = nil
                        Task { await load() }
                    }
                case .edit(let id):
                    if let post = rows.first(where: { $0.id == id }) {
                        PostFormView(post: post, onClose: { mobileForm = nil }) {
                            mobileForm = nil
                            Task { await load() }
                        }
                    }
                case .detail(let id):
                    if let post = rows.first(where: { $0.id == id }) {
                        PostDetailView(post: post, onClose: { mobileForm = nil })
                    }
                }
            }
        }
    }

    private var desktopList: some View {
        WireCard(fullHeight: true) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    WireButton(title: L("button.add"), icon: "add-circle", variant: .primary) {
                        active = tabs.open(name: "add-\(Int(Date().timeIntervalSince1970))", title: L("button.add"))
                    }
                    WireButton(title: L("button.batchDelete"), icon: "delete", variant: .danger, disabled: selected.isEmpty) {
                        showBatchDelete = true
                    }
                    Spacer()
                }
                .padding(12)

                WireTable(columns: columns, rowCount: rows.count, selectable: true, selection: selectedIndexes()) { idx in
                    let id = rows[idx].id
                    if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
                } rowAction: { idx in
                    row(idx)
                }

                PaginationBar(total: total, page: $page, pageSize: $pageSize) {
                    Task { await load() }
                }
            }
        }
    }

    private var mobileList: some View {
        ZStack(alignment: .bottomTrailing) {
            MobileCardList(
                cards: rows.map(mobileCard),
                total: total,
                selection: $selected,
                batchActions: [
                    .init(title: L("button.batchDelete"), role: .danger) { showBatchDelete = true },
                ],
                onLoadMore: hasMore ? { await loadMore() } : nil,
                hasMore: hasMore
            )
            if selected.isEmpty {
                MobileFAB { mobileForm = .add }
                    .padding(.trailing, 16)
                    .padding(.bottom, 18)
            }
        }
    }

    private func mobileCard(for post: SysPost) -> MobileCardModel {
        MobileCardModel(
            id: post.id,
            title: post.postName,
            subtitle: post.postCode,
            initials: String(post.postName.prefix(1)),
            showBadge: true,
            badgeText: post.status == 1 ? L("eum.status.enable") : L("eum.status.disable"),
            badgeKind: post.status == 1 ? .success : .danger,
            fields: [
                .init(label: L("eum.sort"), value: "\(post.postSort)"),
                .init(label: L("eum.remark"), value: post.remark.isEmpty ? "-" : post.remark),
                .init(label: L("eum.createTime"), value: String(post.createTime.prefix(19))),
            ],
            actions: [
                .init(title: L("button.detail")) { mobileForm = .detail(post.id) },
                .init(title: L("button.edit")) { mobileForm = .edit(post.id) },
                .init(title: post.status == 1 ? L("eum.status.disable") : L("eum.status.enable")) {
                    Task { await toggleStatus(post, post.status != 1) }
                },
            ]
        )
    }

    /// 手机端筛选弹层
    private var filterSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("状态")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                        HStack(spacing: 8) {
                            ForEach(DictOption.eumStatus) { opt in
                                Button {
                                    status = status == opt.value ? nil : opt.value
                                } label: {
                                    Text(opt.label)
                                        .font(.system(size: 13))
                                        .foregroundColor(status == opt.value ? .white : Theme.text)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .background(status == opt.value ? Theme.primary : Theme.panelBG)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(status == opt.value ? Theme.primary : Theme.border, lineWidth: 1)
                                        )
                                        .clipShape(RoundedCorner(radius: 8))
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("岗位编码")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                        TextField("请输入岗位编码", text: $postCode)
                            .font(.system(size: 13))
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(Theme.panelBG)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                    }
                    HStack(spacing: 10) {
                        WireButton(title: L("button.reset"), variant: .defaultPlain) {
                            postCode = ""
                            status = nil
                        }
                        WireButton(title: L("button.confirm"), variant: .primary) {
                            showFilter = false
                            page = 1
                            Task { await load() }
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

    private func row(_ idx: Int) -> some View {
        let post = rows[idx]
        return HStack(spacing: 0) {
            TableCell(text: "\(idx + 1 + (page - 1) * pageSize)", width: 60, align: .center, color: Theme.textSecondary)
            TableCell(text: post.postCode)
            TableCell(text: post.postName)
            TableCell(text: "\(post.postSort)", width: 80, align: .center)
            HStack {
                StatusSwitch(isOn: post.status == 1) { on in
                    Task { await toggleStatus(post, on) }
                }
            }
            .frame(width: 70, alignment: .center)
            HStack(spacing: 10) {
                WireButton(title: L("button.detail"), icon: "book", variant: .linkPrimary, small: true) {
                    active = tabs.open(name: "detail-\(post.id)", title: String(format: L("tab.detail"), post.postName))
                }
                WireButton(title: L("button.edit"), icon: "pencil", variant: .linkPrimary, small: true) {
                    active = tabs.open(name: "edit-\(post.id)", title: String(format: L("tab.edit"), post.postName))
                }
            }
            .frame(width: 130, alignment: .center)
        }
    }

    @ViewBuilder
    private var tabSections: some View {
        ForEach(tabs) { tab in
            if active == tab.name {
                WireCard(fullHeight: true) {
                    if tab.name.hasPrefix("add-") {
                        PostFormView(onClose: { closeTab(tab.name) }) {
                            closeTab(tab.name)
                            Task { await load() }
                        }
                    } else if tab.name.hasPrefix("edit-") {
                        let id = Int(tab.name.replacingOccurrences(of: "edit-", with: "")) ?? 0
                        if let post = rows.first(where: { $0.id == id }) {
                            PostFormView(post: post, onClose: { closeTab(tab.name) }) {
                                closeTab(tab.name)
                                Task { await load() }
                            }
                        }
                    } else if tab.name.hasPrefix("detail-") {
                        let id = Int(tab.name.replacingOccurrences(of: "detail-", with: "")) ?? 0
                        if let post = rows.first(where: { $0.id == id }) {
                            PostDetailView(post: post, onClose: { closeTab(tab.name) })
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

    private func selectedIndexes() -> Set<Int> {
        Set(rows.enumerated().compactMap { selected.contains($0.element.id) ? $0.offset : nil })
    }

    private func load(append: Bool = false) async {
        loading = true
        defer { loading = false }
        do {
            let r = try await store.postPage(page: page, size: pageSize, postCode: postCode, postName: postName, status: status)
            rows = append ? rows + r.content : r.content
            total = r.total
            hasMore = !r.content.isEmpty && rows.count < r.total
            if !append { selected.removeAll() }
        } catch {
            if append { page -= 1 }
            app.toastError("加载失败")
        }
    }

    private func loadMore() async {
        guard !loading, hasMore else { return }
        page += 1
        await load(append: true)
    }

    private func toggleStatus(_ post: SysPost, _ on: Bool) async {
        do {
            try await store.postStatus(id: post.id, status: on ? 1 : 0)
            rows = rows.map { $0.id == post.id ? post : $0 }
            app.toastSuccess(L("user.statusChanged"))
        } catch {
            app.toast(error, fallback: "操作失败")
        }
    }

    private func doBatchDelete() async {
        do {
            try await store.postDelete(ids: Array(selected))
            app.toastSuccess("删除成功")
        } catch {
            app.toast(error, fallback: "删除失败")
        }
        selected.removeAll()
        await load()
    }
}

// MARK: - 岗位表单 / 详情

struct PostFormView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    var post: SysPost? = nil
    var onClose: () -> Void
    var onSuccess: () -> Void

    @State private var form = SysPost(id: 0, postName: "", postCode: "")
    @State private var loading = false
    private var isEdit: Bool { post != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(isEdit ? "编辑岗位" : "新增岗位")
                    .font(.system(size: 16, weight: .semibold))

                FormTextField(label: L("eum.post.read.postName"), required: true, placeholder: "请输入岗位名称", text: $form.postName)
                FormTextField(label: L("eum.post.read.postCode"), required: true, placeholder: "请输入岗位编码", text: $form.postCode)
                FormNumberField(label: "显示排序", required: true, value: $form.postSort)
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
            if let post { form = post }
        }
    }

    private func submit() async {
        guard !form.postName.isEmpty else { app.toastError("岗位名称不能为空"); return }
        guard !form.postCode.isEmpty else { app.toastError("岗位编码不能为空"); return }
        loading = true
        defer { loading = false }
        do {
            if isEdit {
                try await store.postUpdate(form)
                app.toastSuccess("修改成功")
            } else {
                try await store.postInsert(form)
                app.toastSuccess("新增成功")
            }
            onSuccess()
        } catch {
            app.toast(error, fallback: "提交失败")
        }
    }
}

struct PostDetailView: View {
    let post: SysPost
    var onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("岗位详情")
                    .font(.system(size: 16, weight: .semibold))
                DetailGrid(items: [
                    .init(label: L("eum.post.read.postCode"), value: post.postCode),
                    .init(label: L("eum.post.read.postName"), value: post.postName),
                    .init(label: L("eum.sort"), value: "\(post.postSort)"),
                    .init(label: L("eum.status"), value: Theme.statusText(post.status)),
                    .init(label: L("eum.createBy"), value: post.createBy),
                    .init(label: L("eum.createTime"), value: post.createTime),
                    .init(label: L("eum.remark"), value: post.remark.isEmpty ? "-" : post.remark, span2: true),
                ])
                HStack {
                    Spacer()
                    WireButton(title: L("button.close"), variant: .defaultPlain, action: onClose)
                }
            }
            .padding(20)
        }
    }
}
