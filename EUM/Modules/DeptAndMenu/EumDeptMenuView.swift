import SwiftUI

// MARK: - 部门管理（树形表格，默认展开）

struct EumDeptView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var deptName = ""
    @State private var status: Int?
    @State private var tabs: [DynTab] = []
    @State private var active = "list"
    @State private var deleteTarget: SysDept?
    @State private var statusTarget: SysDept?
    @State private var mobileForm: MobileTarget?

    enum MobileTarget: Identifiable {
        case add, detail(SysDept), edit(SysDept)
        var id: String {
            switch self {
            case .add: return "add"
            case .detail(let d): return "detail-\(d.id)"
            case .edit(let d): return "edit-\(d.id)"
            }
        }
        var title: String {
            switch self {
            case .add: return "新增部门"
            case .detail(let d): return "详情 - \(d.deptName)"
            case .edit(let d): return "编辑 - \(d.deptName)"
            }
        }
    }

    private var isCompact: Bool { hSize == .compact }

    private var columns: [TableCol] = [
        .init(L("eum.dept.read.deptName"), 200),
        .init(L("biz.owner"), 110),
        .init(L("eum.dept.read.phone"), 130),
        .init(L("eum.user.read.email"), 170),
        .init(L("eum.sort"), 70, align: .center),
        .init(L("eum.status"), 70, align: .center),
        .init(L("eum.operation"), 260, align: .center),
    ]

    /// 扁平化（带层级）的可见行
    private var flatRows: [(dept: SysDept, depth: Int)] {
        var result: [(SysDept, Int)] = []
        func walk(_ list: [SysDept], depth: Int) {
            for d in list.sorted(by: { $0.orderNum < $1.orderNum }) {
                result.append((d, depth))
                walk(d.children, depth: depth + 1)
            }
        }
        walk(store.depts, depth: 0)
        return result
    }

    var body: some View {
        PageLayout(header: headerSection, scrolls: !isCompact) {
            if active == "list" {
                listSection
            } else {
                tabSections
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            QueryForm {
                QueryField(label: L("eum.dept.read.deptName"), text: $deptName)
                QueryPickerField(label: L("eum.status"), value: $status, options: DictOption.eumStatus)
            } onSearch: {
                app.toastInfo("已按条件刷新")
            } onReset: {
                deptName = ""; status = nil
            }
            DynTabBar(tabs: $tabs, active: $active, fixedTitle: L("list.depts"))
        }
    }

    private var filteredRows: [(dept: SysDept, depth: Int)] {
        var rows = flatRows
        if !deptName.isEmpty {
            rows = rows.filter { $0.dept.deptName.localizedCaseInsensitiveContains(deptName) }
        }
        if let s = status {
            rows = rows.filter { $0.dept.status == s }
        }
        return rows
    }

    private var listSection: some View {
        Group {
            if isCompact {
                mobileList
            } else {
                desktopList
            }
        }
        .confirmationDialog(String(format: L("dept.confirmDelete"), deleteTarget?.deptName ?? ""),
                            isPresented: Binding(get: { deleteTarget != nil },
                                                 set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
            Button(L("button.delete"), role: .destructive) {
                if let dept = deleteTarget { Task { await deleteDept(dept) } }
                deleteTarget = nil
            }
            Button(L("button.cancel"), role: .cancel) { deleteTarget = nil }
        }
        .confirmationDialog("确认\(statusTarget?.status == 1 ? L("eum.status.disable") : L("eum.status.enable"))部门「\(statusTarget?.deptName ?? "")」吗？",
                            isPresented: Binding(get: { statusTarget != nil },
                                                 set: { if !$0 { statusTarget = nil } }),
                            titleVisibility: .visible) {
            Button(statusTarget?.status == 1 ? L("eum.status.disable") : L("eum.status.enable"), role: .destructive) {
                if let dept = statusTarget { Task { await toggleDeptStatus(dept) } }
                statusTarget = nil
            }
            Button(L("button.cancel"), role: .cancel) { statusTarget = nil }
        }
        .sheet(item: $mobileForm) { target in
            MobileSheetContainer(title: target.title) {
                switch target {
                case .add:
                    DeptFormView(onClose: { mobileForm = nil }) {
                        mobileForm = nil
                        Task { await store.loadDeptTree() }
                    }
                case .edit(let dept):
                    DeptFormView(dept: dept, onClose: { mobileForm = nil }) {
                        mobileForm = nil
                        Task { await store.loadDeptTree() }
                    }
                case .detail(let dept):
                    DeptDetailView(dept: dept, onClose: { mobileForm = nil })
                }
            }
        }
        .task {
            await store.loadDeptTree()
        }
    }

    /// 手机端：部门树拍平为缩进卡片
    private var mobileList: some View {
        ZStack(alignment: .bottomTrailing) {
            MobileCardList(
                cards: filteredRows.map { mobileCard(for: $0.dept, depth: $0.depth) },
                total: filteredRows.count,
                selection: .constant([]),
                onLoadMore: nil,
                hasMore: false
            )
            MobileFAB { mobileForm = .add }
                .padding(.trailing, 16)
                .padding(.bottom, 18)
        }
    }

    private func mobileCard(for dept: SysDept, depth: Int) -> MobileCardModel {
        MobileCardModel(
            id: dept.id,
            title: String(repeating: "　", count: depth) + dept.deptName,
            subtitle: depth == 0 ? "根部门" : "上级：\(store.deptName(dept.parentId))",
            initials: String(dept.deptName.prefix(1)),
            showBadge: true,
            badgeText: dept.status == 1 ? L("eum.status.enable") : L("eum.status.disable"),
            badgeKind: dept.status == 1 ? .success : .danger,
            fields: [
                .init(label: L("biz.owner"), value: dept.leader.isEmpty ? "-" : dept.leader),
                .init(label: L("eum.dept.read.phone"), value: dept.phone.isEmpty ? "-" : dept.phone),
                .init(label: L("eum.user.read.email"), value: dept.email.isEmpty ? "-" : dept.email),
                .init(label: L("eum.sort"), value: "\(dept.orderNum)"),
            ],
            actions: [
                .init(title: L("button.detail")) { mobileForm = .detail(dept) },
                .init(title: L("button.edit")) { mobileForm = .edit(dept) },
                .init(title: dept.status == 1 ? L("eum.status.disable") : L("eum.status.enable")) { statusTarget = dept },
                .init(title: L("button.delete"), role: .danger) { deleteTarget = dept },
            ]
        )
    }

    private var desktopList: some View {
        WireCard(fullHeight: true) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    WireButton(title: L("button.add"), icon: "add-circle", variant: .primary) {
                        active = tabs.open(name: "add-\(Int(Date().timeIntervalSince1970))", title: L("button.add"))
                    }
                    Spacer()
                }
                .padding(12)

                WireTable(columns: columns, rowCount: filteredRows.count) { idx in
                    row(idx)
                }
            }
        }
    }

    private func deleteDept(_ dept: SysDept) async {
        do {
            try await store.deptDelete(ids: [dept.id])
            app.toastSuccess("删除成功")
        } catch {
            app.toast(error, fallback: "删除失败")
        }
        await store.loadDeptTree()
    }

    private func toggleDeptStatus(_ dept: SysDept) async {
        do {
            try await store.deptStatus(id: dept.id, status: dept.status == 1 ? 0 : 1)
            app.toastSuccess(L("user.statusChanged"))
        } catch {
            app.toast(error, fallback: "操作失败")
        }
        await store.loadDeptTree()
    }

    private func row(_ idx: Int) -> some View {
        let item = filteredRows[idx]
        let dept = item.dept
        return TreeCellsRow(
            columns: columns,
            cells: [
                treeCell(dept.deptName, width: 200),
                treeCell(dept.leader.isEmpty ? "-" : dept.leader, width: 110),
                treeCell(dept.phone, width: 130),
                treeCell(dept.email, width: 170),
                treeCell("\(dept.orderNum)", width: 70, align: .center, color: Theme.textSecondary),
                treeCell(Theme.statusText(dept.status), width: 70, align: .center, color: dept.status == 1 ? Theme.success : Theme.danger),
                treeCell("", width: 260),
            ],
            depth: item.depth,
            hasChildren: !dept.children.isEmpty,
            isExpanded: true,
            onToggle: nil
        )
        .overlay(alignment: .trailing) {
            HStack(spacing: 10) {
                WireButton(title: dept.status == 1 ? L("eum.status.disable") : L("eum.status.enable"),
                           icon: "operation",
                           variant: .linkPlain, small: true) {
                    statusTarget = dept
                }
                WireButton(title: L("button.detail"), icon: "book", variant: .linkPrimary, small: true) {
                    active = tabs.open(name: "detail-\(dept.id)", title: String(format: L("tab.detail"), dept.deptName))
                }
                WireButton(title: L("button.edit"), icon: "pencil", variant: .linkPrimary, small: true) {
                    active = tabs.open(name: "edit-\(dept.id)", title: String(format: L("tab.edit"), dept.deptName))
                }
                WireButton(title: L("button.delete"), icon: "delete", variant: .linkDanger, small: true) {
                    deleteTarget = dept
                }
            }
            .frame(width: 260, alignment: .center)
            .padding(.trailing, 8)
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var tabSections: some View {
        ForEach(tabs) { tab in
            if active == tab.name {
                WireCard(fullHeight: true) {
                    if tab.name.hasPrefix("add-") {
                        DeptFormView(onClose: { closeTab(tab.name) }) {
                            closeTab(tab.name)
                        }
                    } else if tab.name.hasPrefix("edit-") {
                        let id = Int(tab.name.replacingOccurrences(of: "edit-", with: "")) ?? 0
                        if let dept = findDept(id) {
                            DeptFormView(dept: dept, onClose: { closeTab(tab.name) }) {
                                closeTab(tab.name)
                            }
                        }
                    } else if tab.name.hasPrefix("detail-") {
                        let id = Int(tab.name.replacingOccurrences(of: "detail-", with: "")) ?? 0
                        if let dept = findDept(id) {
                            DeptDetailView(dept: dept, onClose: { closeTab(tab.name) })
                        }
                    }
                }
            }
        }
    }

    private func findDept(_ id: Int) -> SysDept? {
        for d in store.depts {
            if let f = d.flattened().first(where: { $0.id == id }) { return f }
        }
        return nil
    }

    private func closeTab(_ name: String) {
        tabs.removeAll { $0.name == name }
        if active == name { active = "list" }
    }
}

// MARK: - 部门表单

struct DeptFormView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    var dept: SysDept? = nil
    var onClose: () -> Void
    var onSuccess: () -> Void

    @State private var form = SysDept(id: 0, parentId: 0, deptName: "")
    @State private var showParentPicker = false
    @State private var loading = false

    private var isEdit: Bool { dept != nil }

    private var parentName: String {
        form.parentId == 0 ? "无上级部门" : (store.depts.flatMap { $0.flattened() }.first { $0.id == form.parentId }?.deptName ?? "-")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(isEdit ? "编辑部门" : "新增部门")
                    .font(.system(size: 16, weight: .semibold))

                HStack(spacing: 8) {
                    FormFieldLabel(text: L("dept.parent"), required: true)
                    Button {
                        showParentPicker = true
                    } label: {
                        HStack {
                            Text(parentName).font(.system(size: 13)).foregroundColor(Theme.text)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundColor(Theme.textTertiary)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .background(Theme.panelBG)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                FormTextField(label: L("eum.dept.read.deptName"), required: true, placeholder: "请输入部门名称", text: $form.deptName)
                FormNumberField(label: "显示排序", required: true, value: $form.orderNum)
                FormTextField(label: L("biz.owner"), placeholder: "请输入负责人", text: $form.leader)
                FormTextField(label: L("eum.dept.read.phone"), placeholder: "请输入电话", text: $form.phone)
                FormTextField(label: L("eum.user.read.email"), placeholder: "请输入邮箱", text: $form.email)
                FormRadioRow(label: "状态", options: [(1, "启用"), (0, "停用")], value: $form.status)

                FormActions(loading: loading) {
                    onClose()
                } onConfirm: {
                    Task { await submit() }
                }
            }
            .padding(20)
        }
        .onAppear {
            if let dept { form = dept }
        }
        .sheet(isPresented: $showParentPicker) {
            DeptTreePicker(selected: Binding(
                get: { DeptPick(id: form.parentId, name: "") },
                set: { form.parentId = $0?.id ?? 0 }
            ))
        }
    }

    private func submit() async {
        guard !form.deptName.isEmpty else { app.toastError("部门名称不能为空"); return }
        loading = true
        defer { loading = false }
        do {
            if isEdit {
                try await store.deptUpdate(form)
                app.toastSuccess("修改成功")
            } else {
                try await store.deptInsert(form)
                app.toastSuccess("新增成功")
            }
            await store.loadDeptTree()
            onSuccess()
        } catch {
            app.toast(error, fallback: "提交失败")
        }
    }
}

// MARK: - 部门详情

struct DeptDetailView: View {
    @EnvironmentObject var store: DataService
    let dept: SysDept
    var onClose: () -> Void

    private var ancestors: String {
        var path: [String] = []
        func walk(_ list: [SysDept], stack: [String]) {
            for d in list {
                var s = stack; s.append(d.deptName)
                if d.id == dept.id { path = s.dropLast(); return }
                walk(d.children, stack: s)
            }
        }
        walk(store.depts, stack: [])
        return path.isEmpty ? "无" : path.joined(separator: "，")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("部门详情")
                    .font(.system(size: 16, weight: .semibold))
                DetailGrid(items: [
                    .init(label: L("dept.parent"), value: dept.parentId == 0 ? "无" : (store.depts.flatMap { $0.flattened() }.first { $0.id == dept.parentId }?.deptName ?? "-")),
                    .init(label: L("eum.dept.read.ancestors"), value: ancestors),
                    .init(label: L("eum.dept.read.deptName"), value: dept.deptName),
                    .init(label: L("eum.sort"), value: "\(dept.orderNum)"),
                    .init(label: L("biz.owner"), value: dept.leader.isEmpty ? "-" : dept.leader),
                    .init(label: L("eum.dept.read.phone"), value: dept.phone.isEmpty ? "-" : dept.phone),
                    .init(label: L("eum.user.read.email"), value: dept.email.isEmpty ? "-" : dept.email),
                    .init(label: L("eum.status"), value: Theme.statusText(dept.status)),
                    .init(label: L("eum.createTime"), value: dept.createTime),
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

// MARK: - 菜单管理（树形表格，默认折叠）

struct EumMenuView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var menuName = ""
    @State private var status: Int?
    @State private var expanded: Set<Int> = [1, 4]   // 默认展开顶层
    @State private var tabs: [DynTab] = []
    @State private var active = "list"
    @State private var deleteTarget: SysMenu?
    @State private var statusTarget: SysMenu?
    @State private var mobileForm: MobileTarget?

    enum MobileTarget: Identifiable {
        case add, detail(SysMenu), edit(SysMenu)
        var id: String {
            switch self {
            case .add: return "add"
            case .detail(let m): return "detail-\(m.id)"
            case .edit(let m): return "edit-\(m.id)"
            }
        }
        var title: String {
            switch self {
            case .add: return "新增菜单"
            case .detail(let m): return "详情 - \(m.translatedName)"
            case .edit(let m): return "编辑 - \(m.translatedName)"
            }
        }
    }

    private var isCompact: Bool { hSize == .compact }

    private var columns: [TableCol] = [
        .init(L("eum.menu.read.menuName"), 170),
        .init(L("eum.menu.read.icon"), 46, align: .center),
        .init(L("eum.sort"), 60, align: .center),
        .init(L("eum.menu.read.perms"), 130),
        .init(L("eum.menu.read.component"), 150),
        .init(L("eum.status"), 60, align: .center),
        .init(L("eum.operation"), 260, align: .center),
    ]

    private var flatRows: [(menu: SysMenu, depth: Int, hasChildren: Bool)] {
        var result: [(SysMenu, Int, Bool)] = []
        func walk(_ list: [SysMenu], depth: Int) {
            for m in list.sorted(by: { $0.orderNum < $1.orderNum }) {
                let hasKids = !m.children.isEmpty
                result.append((m, depth, hasKids))
                if hasKids && expanded.contains(m.id) {
                    walk(m.children, depth: depth + 1)
                }
            }
        }
        walk(store.menus, depth: 0)
        return result
    }

    var body: some View {
        PageLayout(header: headerSection, scrolls: !isCompact) {
            if active == "list" {
                listSection
            } else {
                tabSections
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            if isCompact {
                MobileSearchBar(text: $menuName,
                                placeholder: String(format: L("common.searchFormat"), L("eum.menu.read.menuName")),
                                filterCount: status == nil ? 0 : 1,
                                onFilter: {},
                                onSubmit: { app.toastInfo("已按条件刷新") })
                FilterChipsBar(chips: filterChips, onClearAll: {
                    status = nil
                })
            } else {
                QueryForm {
                    QueryField(label: L("eum.menu.read.menuName"), text: $menuName)
                    QueryPickerField(label: L("eum.status"), value: $status, options: DictOption.eumStatus)
                } onSearch: {
                    app.toastInfo("已按条件刷新")
                } onReset: {
                    menuName = ""; status = nil
                }
                DynTabBar(tabs: $tabs, active: $active, fixedTitle: L("list.menus"))
            }
        }
    }

    private var filterChips: [MobileFilterChip] {
        guard let status else { return [] }
        return [.init(id: "status", label: "状态：\(DictOption.eumStatus.first { $0.value == status }?.label ?? "\(status)")", onRemove: {
            self.status = nil
        })]
    }

    private var filteredRows: [(menu: SysMenu, depth: Int, hasChildren: Bool)] {
        var rows = flatRows
        if !menuName.isEmpty {
            rows = rows.filter { $0.menu.menuName.localizedCaseInsensitiveContains(menuName) }
        }
        if let s = status {
            rows = rows.filter { $0.menu.status == s }
        }
        return rows
    }

    private var listSection: some View {
        Group {
            if isCompact {
                mobileList
            } else {
                desktopList
            }
        }
        .confirmationDialog(String(format: L("menu.confirmDelete"), deleteTarget?.translatedName ?? ""),
                            isPresented: Binding(get: { deleteTarget != nil },
                                                 set: { if !$0 { deleteTarget = nil } }),
                            titleVisibility: .visible) {
            Button(L("button.delete"), role: .destructive) {
                if let menu = deleteTarget { Task { await deleteMenu(menu) } }
                deleteTarget = nil
            }
            Button(L("button.cancel"), role: .cancel) { deleteTarget = nil }
        }
        .confirmationDialog("确认\(statusTarget?.status == 1 ? L("eum.status.disable") : L("eum.status.enable"))菜单「\(statusTarget?.translatedName ?? "")」吗？",
                            isPresented: Binding(get: { statusTarget != nil },
                                                 set: { if !$0 { statusTarget = nil } }),
                            titleVisibility: .visible) {
            Button(statusTarget?.status == 1 ? L("eum.status.disable") : L("eum.status.enable"), role: .destructive) {
                if let menu = statusTarget { Task { await toggleMenuStatus(menu) } }
                statusTarget = nil
            }
            Button(L("button.cancel"), role: .cancel) { statusTarget = nil }
        }
        .sheet(item: $mobileForm) { target in
            MobileSheetContainer(title: target.title) {
                switch target {
                case .add:
                    MenuFormView(onClose: { mobileForm = nil }) {
                        mobileForm = nil
                        Task { await store.loadMenus() }
                    }
                case .edit(let menu):
                    MenuFormView(menu: menu, onClose: { mobileForm = nil }) {
                        mobileForm = nil
                        Task { await store.loadMenus() }
                    }
                case .detail(let menu):
                    MenuDetailView(menu: menu, onClose: { mobileForm = nil })
                }
            }
        }
        .task {
            await store.loadMenus()
        }
    }

    /// 手机端：菜单树拍平为缩进卡片
    private var mobileList: some View {
        ZStack(alignment: .bottomTrailing) {
            MobileCardList(
                cards: filteredRows.map { mobileCard(for: $0.menu, depth: $0.depth) },
                total: filteredRows.count,
                selection: .constant([]),
                onLoadMore: nil,
                hasMore: false
            )
            MobileFAB { mobileForm = .add }
                .padding(.trailing, 16)
                .padding(.bottom, 18)
        }
    }

    private func mobileCard(for menu: SysMenu, depth: Int) -> MobileCardModel {
        let typeText = menu.menuType == 1 ? "目录" : (menu.menuType == 2 ? "菜单" : "按钮")
        return MobileCardModel(
            id: menu.id,
            title: String(repeating: "　", count: depth) + menu.translatedName,
            subtitle: "\(typeText)\(menu.component.isEmpty ? "" : " · \(menu.component)")",
            initials: String(menu.translatedName.prefix(1)),
            showBadge: true,
            badgeText: menu.status == 1 ? L("eum.status.enable") : L("eum.status.disable"),
            badgeKind: menu.status == 1 ? .success : .danger,
            fields: [
                .init(label: L("eum.menu.read.perms"), value: menu.perms.isEmpty ? "-" : menu.perms),
                .init(label: L("eum.sort"), value: "\(menu.orderNum)"),
            ],
            actions: [
                .init(title: L("button.detail")) { mobileForm = .detail(menu) },
                .init(title: L("button.edit")) { mobileForm = .edit(menu) },
                .init(title: menu.status == 1 ? L("eum.status.disable") : L("eum.status.enable")) { statusTarget = menu },
                .init(title: L("button.delete"), role: .danger) { deleteTarget = menu },
            ]
        )
    }

    private var desktopList: some View {
        WireCard(fullHeight: true) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    WireButton(title: L("button.add"), icon: "add-circle", variant: .primary) {
                        active = tabs.open(name: "add-\(Int(Date().timeIntervalSince1970))", title: L("button.add"))
                    }
                    Spacer()
                    if expanded.isEmpty {
                        WireButton(title: L("tree.expandAll"), icon: "list", variant: .ghost, small: true) {
                            expanded = Set(store.menus.flatMap { $0.flattenedMenuIdsForExpand() })
                        }
                    } else {
                        WireButton(title: L("tree.collapseAll"), icon: "list", variant: .ghost, small: true) {
                            expanded = []
                        }
                    }
                }
                .padding(12)

                WireTable(columns: columns, rowCount: filteredRows.count) { idx in
                    row(idx)
                }
            }
        }
    }

    private func deleteMenu(_ menu: SysMenu) async {
        do {
            try await store.menuDelete(ids: [menu.id])
            app.toastSuccess("删除成功")
        } catch {
            app.toast(error, fallback: "删除失败")
        }
        await store.loadMenus()
    }

    private func toggleMenuStatus(_ menu: SysMenu) async {
        do {
            try await store.menuStatus(id: menu.id, status: menu.status == 1 ? 0 : 1)
            app.toastSuccess(L("user.statusChanged"))
        } catch {
            app.toast(error, fallback: "操作失败")
        }
        await store.loadMenus()
    }

    private func row(_ idx: Int) -> some View {
        let item = filteredRows[idx]
        let menu = item.menu
        return TreeCellsRow(
            columns: columns,
            cells: [
                treeCell(menu.translatedName, width: 170),
                treeCell(menu.icon == "#" ? "" : menu.icon, width: 46, align: .center, color: Theme.textSecondary),
                treeCell("\(menu.orderNum)", width: 60, align: .center, color: Theme.textSecondary),
                treeCell(menu.perms.isEmpty ? "-" : menu.perms, width: 130, mono: true, color: Theme.textSecondary),
                treeCell(menu.component.isEmpty ? "-" : menu.component, width: 150, mono: true, color: Theme.textSecondary),
                treeCell(Theme.statusText(menu.status), width: 60, align: .center, color: menu.status == 1 ? Theme.success : Theme.danger),
                treeCell("", width: 260),
            ],
            depth: item.depth,
            hasChildren: item.hasChildren,
            isExpanded: expanded.contains(menu.id),
            onToggle: {
                if expanded.contains(menu.id) { expanded.remove(menu.id) } else { expanded.insert(menu.id) }
            }
        )
        .overlay(alignment: .trailing) {
            HStack(spacing: 10) {
                WireButton(title: menu.status == 1 ? L("eum.status.disable") : L("eum.status.enable"),
                           icon: "operation", variant: .linkPlain, small: true) {
                    statusTarget = menu
                }
                WireButton(title: L("button.detail"), icon: "book", variant: .linkPrimary, small: true) {
                    active = tabs.open(name: "detail-\(menu.id)", title: String(format: L("tab.detail"), menu.menuName))
                }
                WireButton(title: L("button.edit"), icon: "pencil", variant: .linkPrimary, small: true) {
                    active = tabs.open(name: "edit-\(menu.id)", title: String(format: L("tab.edit"), menu.menuName))
                }
                WireButton(title: L("button.delete"), icon: "delete", variant: .linkDanger, small: true) {
                    deleteTarget = menu
                }
            }
            .frame(width: 260, alignment: .center)
            .padding(.trailing, 8)
        }
    }

    @ViewBuilder
    private var tabSections: some View {
        ForEach(tabs) { tab in
            if active == tab.name {
                WireCard(fullHeight: true) {
                    if tab.name.hasPrefix("add-") {
                        MenuFormView(onClose: { closeTab(tab.name) }) {
                            closeTab(tab.name)
                        }
                    } else if tab.name.hasPrefix("edit-") {
                        let id = Int(tab.name.replacingOccurrences(of: "edit-", with: "")) ?? 0
                        if let menu = findMenu(id) {
                            MenuFormView(menu: menu, onClose: { closeTab(tab.name) }) {
                                closeTab(tab.name)
                            }
                        }
                    } else if tab.name.hasPrefix("detail-") {
                        let id = Int(tab.name.replacingOccurrences(of: "detail-", with: "")) ?? 0
                        if let menu = findMenu(id) {
                            MenuDetailView(menu: menu, onClose: { closeTab(tab.name) })
                        }
                    }
                }
            }
        }
    }

    private func findMenu(_ id: Int) -> SysMenu? {
        func walk(_ list: [SysMenu]) -> SysMenu? {
            for m in list {
                if m.id == id { return m }
                if let f = walk(m.children) { return f }
            }
            return nil
        }
        return walk(store.menus)
    }

    private func closeTab(_ name: String) {
        tabs.removeAll { $0.name == name }
        if active == name { active = "list" }
    }
}

private extension SysMenu {
    func flattenedMenuIdsForExpand() -> [Int] {
        [id] + children.flatMap { $0.flattenedMenuIdsForExpand() }
    }
}

// MARK: - 菜单表单

struct MenuFormView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    var menu: SysMenu? = nil
    var onClose: () -> Void
    var onSuccess: () -> Void

    @State private var form = SysMenu(id: 0, parentId: 0, menuName: "", menuType: 2)
    @State private var showParentPicker = false
    @State private var loading = false

    private var isEdit: Bool { menu != nil }
    private var isButton: Bool { form.menuType == 3 }

    private var parentName: String {
        form.parentId == 0 ? "主类目" : (allMenus.first { $0.id == form.parentId }?.menuName ?? "-")
    }

    private var allMenus: [SysMenu] {
        store.menus.flatMap { $0.flattenedSelf() }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(isEdit ? "编辑菜单" : "新增菜单")
                    .font(.system(size: 16, weight: .semibold))

                // 上级菜单
                HStack(spacing: 8) {
                    FormFieldLabel(text: L("eum.menu.read.parentId"), required: true)
                    Button {
                        showParentPicker = true
                    } label: {
                        HStack {
                            Text(parentName).font(.system(size: 13)).foregroundColor(Theme.text)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundColor(Theme.textTertiary)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 7)
                        .background(Theme.panelBG)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                FormRadioRow(label: "菜单类型", options: [(1, "目录"), (2, "菜单"), (3, "按钮")], value: $form.menuType)
                FormTextField(label: L("eum.menu.read.menuName"), required: true, placeholder: "请输入菜单名称", text: $form.menuName)
                FormNumberField(label: "显示排序", required: true, value: $form.orderNum)

                if !isButton {
                    FormTextField(label: L("eum.menu.read.path"), required: true, placeholder: "请输入路由地址", text: $form.path)
                }
                if form.menuType == 2 {
                    FormTextField(label: L("eum.menu.read.component"), placeholder: "请输入组件路径", text: $form.component)
                }
                if !isButton {
                    FormTextField(label: L("eum.menu.read.routeName"), placeholder: "请输入路由名称", text: $form.routeName)
                    FormRadioRow(label: "是否外链", options: [(0, "是"), (1, "否")], value: $form.isFrame)
                }
                if form.menuType == 2 {
                    FormRadioRow(label: "是否缓存", options: [(0, "是"), (1, "否")], value: $form.isCache)
                }
                if !isButton {
                    FormRadioRow(label: "显示状态", options: [(1, "显示"), (0, "隐藏")], value: $form.visible)
                }
                if !isButton || form.menuType == 2 || isButton {
                    FormTextField(label: L("eum.menu.read.perms"), placeholder: "请输入权限标识", text: $form.perms)
                }
                FormTextField(label: L("eum.menu.read.icon"), placeholder: "点击选择图标或直接输入图标名称", text: $form.icon)
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
            if let menu { form = menu }
        }
        .sheet(isPresented: $showParentPicker) {
            MenuTreePicker(selected: Binding(
                get: { form.parentId },
                set: { form.parentId = $0 ?? 0 }
            ))
        }
    }

    private func submit() async {
        guard !form.menuName.isEmpty else { app.toastError("菜单名称不能为空"); return }
        loading = true
        defer { loading = false }
        do {
            if isEdit {
                try await store.menuUpdate(form)
                app.toastSuccess("修改成功")
            } else {
                try await store.menuInsert(form)
                app.toastSuccess("新增成功")
            }
            // 对齐 web：菜单变更后刷新全局侧边栏
            await store.loadMenus()
            onSuccess()
        } catch {
            app.toast(error, fallback: "提交失败")
        }
    }
}

private extension SysMenu {
    func flattenedSelf() -> [SysMenu] {
        [self] + children.flatMap { $0.flattenedSelf() }
    }
}

// MARK: - 菜单上级选择器

struct MenuTreePicker: View {
    @Binding var selected: Int?
    @EnvironmentObject var store: DataService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    row(name: "主类目", id: 0, depth: 0)
                    ForEach(store.menus.sorted { $0.orderNum < $1.orderNum }) { menu in
                        node(menu, depth: 0)
                    }
                }
            }
            .navigationTitle("上级菜单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L("button.cancel")) { dismiss() }.font(.system(size: 13))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(name: String, id: Int, depth: Int) -> some View {
        let isSel = selected == id
        return Button {
            selected = id
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
        .padding(.leading, CGFloat(depth) * 16)
    }

    private func node(_ menu: SysMenu, depth: Int) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 0) {
                if menu.menuType != 3 {
                    row(name: menu.menuName, id: menu.id, depth: depth)
                }
                ForEach(menu.children.sorted { $0.orderNum < $1.orderNum }) { child in
                    node(child, depth: depth + 1)
                }
            }
        )
    }
}

// MARK: - 菜单详情

struct MenuDetailView: View {
    let menu: SysMenu
    var onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("菜单详情")
                    .font(.system(size: 16, weight: .semibold))
                DetailGrid(items: [
                    .init(label: L("eum.menu.read.menuName"), value: menu.menuName),
                    .init(label: L("eum.menu.read.menuType"), value: menu.menuTypeText),
                    .init(label: L("eum.menu.read.path"), value: menu.path.isEmpty ? "-" : menu.path),
                    .init(label: L("eum.menu.read.component"), value: menu.component.isEmpty ? "-" : menu.component),
                    .init(label: L("eum.menu.read.routeName"), value: menu.routeName.isEmpty ? "-" : menu.routeName),
                    .init(label: L("eum.menu.read.perms"), value: menu.perms.isEmpty ? "-" : menu.perms),
                    .init(label: L("eum.menu.read.icon"), value: menu.icon == "#" ? "-" : menu.icon),
                    .init(label: L("eum.sort"), value: "\(menu.orderNum)"),
                    .init(label: L("eum.menu.read.isFrame"), value: menu.isFrame == 0 ? "是" : "否"),
                    .init(label: L("eum.menu.read.isCache"), value: menu.isCache == 0 ? "是" : "否"),
                    .init(label: L("eum.menu.read.visible"), value: menu.visible == 1 ? "显示" : "隐藏"),
                    .init(label: L("eum.status"), value: Theme.statusText(menu.status)),
                    .init(label: L("eum.createTime"), value: menu.createTime),
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
