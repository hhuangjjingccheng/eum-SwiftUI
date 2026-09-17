import SwiftUI

// MARK: - 账号管理（account，§4.1）

struct AccountView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var accountKey = ""
    @State private var page = 1
    @State private var pageSize = 10
    @State private var total = 0
    @State private var rows: [Account] = []
    @State private var loading = false
    @State private var hasMore = false
    @State private var selected: Set<Int> = []
    @State private var showBatchDelete = false
    @State private var tabs: [DynTab] = []
    @State private var active = "list"
    @State private var mobileForm: MobileTarget?

    enum MobileTarget: Identifiable {
        case add, edit(Int)
        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let id): return "edit-\(id)"
            }
        }
        var title: String {
            switch self {
            case .add: return "新增账号"
            case .edit: return "编辑账号"
            }
        }
    }

    private var isCompact: Bool { hSize == .compact }

    private var columns: [TableCol] = [
        .init(L("eum.index"), 60, align: .center),
        .init(L("account.id"), 140, align: .center),
        .init(L("account.name")),
        .init(L("eum.operation"), 150, align: .center),
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
        .task { await load() }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            if isCompact {
                MobileSearchBar(text: $accountKey,
                                placeholder: String(format: L("common.searchFormat"), L("account.name")),
                                onFilter: {},
                                onSubmit: { page = 1; Task { await load() } })
            } else {
                QueryForm {
                    QueryField(label: L("account.name"), text: $accountKey)
                } onSearch: {
                    page = 1
                    Task { await load() }
                } onReset: {
                    accountKey = ""
                    page = 1
                    Task { await load() }
                }
                DynTabBar(tabs: $tabs, active: $active, fixedTitle: L("list.accounts"))
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
                    AccountFormView(onClose: { mobileForm = nil }) {
                        mobileForm = nil
                        Task { await load() }
                    }
                case .edit(let id):
                    if let account = rows.first(where: { $0.id == id }) {
                        AccountFormView(account: account, onClose: { mobileForm = nil }) {
                            mobileForm = nil
                            Task { await load() }
                        }
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
                WireTable(columns: columns, rowCount: rows.count, selectable: true, selection: selectedIndexes) { idx in
                    onToggleRow(idx)
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

    private func mobileCard(for account: Account) -> MobileCardModel {
        MobileCardModel(
            id: account.id,
            title: account.account,
            subtitle: "ID \(account.id)",
            initials: String(account.account.prefix(1)).uppercased(),
            fields: [],
            actions: [
                .init(title: L("button.edit")) { mobileForm = .edit(account.id) },
                .init(title: L("button.delete"), role: .danger) {
                    selected = [account.id]
                    showBatchDelete = true
                },
            ]
        )
    }

    private func row(_ idx: Int) -> some View {
        let account = rows[idx]
        return HStack(spacing: 0) {
            TableCell(text: "\(idx + 1 + (page - 1) * pageSize)", width: 60, align: .center, color: Theme.textSecondary)
            TableCell(text: "\(account.id)", width: 140, align: .center, mono: true)
            TableCell(text: account.account)
            HStack(spacing: 10) {
                WireButton(title: L("button.edit"), icon: "pencil", variant: .linkPrimary, small: true) {
                    active = tabs.open(name: "edit-\(account.id)", title: String(format: L("tab.edit"), account.account))
                }
                WireButton(title: L("button.delete"), icon: "delete", variant: .linkDanger, small: true) {
                    selected = [account.id]
                    showBatchDelete = true
                }
            }
            .frame(width: 150, alignment: .center)
        }
    }

    @ViewBuilder
    private var formAndDetailSections: some View {
        ForEach(tabs) { tab in
            if active == tab.name {
                WireCard(fullHeight: true) {
                    if tab.name.hasPrefix("add-") {
                        AccountFormView(onClose: { closeTab(tab.name) }) {
                            closeTab(tab.name)
                            Task { await load() }
                        }
                    } else if tab.name.hasPrefix("edit-") {
                        let id = Int(tab.name.replacingOccurrences(of: "edit-", with: "")) ?? 0
                        if let account = rows.first(where: { $0.id == id }) {
                            AccountFormView(account: account, onClose: { closeTab(tab.name) }) {
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

    private func load(append: Bool = false) async {
        loading = true
        defer { loading = false }
        do {
            let result = try await store.accountPage(page: page, size: pageSize, account: accountKey)
            rows = append ? rows + result.content : result.content
            total = result.total
            hasMore = !result.content.isEmpty && rows.count < total
            if !append { selected.removeAll() }
        } catch {
            if append { page -= 1 }
            app.toast(error, fallback: "加载失败")
        }
    }

    private func loadMore() async {
        guard !loading, hasMore else { return }
        page += 1
        await load(append: true)
    }

    private func doBatchDelete() async {
        do {
            try await store.accountDelete(ids: Array(selected))
            app.toastSuccess("删除成功")
            selected.removeAll()
        } catch {
            app.toast(error, fallback: "删除失败")
        }
        await load()
    }
}

// MARK: 账号表单（§4.1.1 插入要求 accountId 必填，与后端约定一致）

struct AccountFormView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    var account: Account? = nil
    var onClose: () -> Void
    var onSuccess: () -> Void

    @State private var idText = ""
    @State private var name = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var loading = false

    private var isEdit: Bool { account != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(isEdit ? "编辑账号" : "新增账号")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text)

                if isEdit {
                    DetailGrid(items: [.init(label: L("account.id"), value: "\(account?.id ?? 0)")])
                } else {
                    HStack(spacing: 8) {
                        FormFieldLabel(text: L("account.id"), required: true)
                        TextField("请输入数字 ID", text: $idText)
                            .font(.system(size: 13))
                            .keyboardType(.numberPad)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Theme.panelBG)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                    }
                }
                FormTextField(label: L("account.name"), required: true, placeholder: "请输入账号名称", text: $name)
                FormTextField(label: L("auth.login.password"), required: !isEdit, placeholder: isEdit ? "留空则不修改" : "请输入密码", text: $password)
                if !isEdit {
                    FormTextField(label: L("user.confirmPassword"), required: true, placeholder: "请再次输入密码", text: $confirmPassword)
                }

                FormActions(loading: loading) {
                    onClose()
                } onConfirm: {
                    Task { await submit() }
                }
            }
            .padding(20)
        }
        .onAppear {
            if let account {
                idText = "\(account.id)"
                name = account.account
            }
        }
    }

    private func submit() async {
        guard let id = Int(idText), id > 0 else { app.toastError("账号 ID 必须为正整数"); return }
        guard !name.isEmpty else { app.toastError("账号名称不能为空"); return }
        if !isEdit {
            guard !password.isEmpty else { app.toastError("密码不能为空"); return }
            guard password == confirmPassword else { app.toastError("两次输入的密码不一致"); return }
        }
        loading = true
        defer { loading = false }
        do {
            if isEdit {
                try await store.accountUpdate(id: id, account: name,
                                              password: password.isEmpty ? nil : password)
                app.toastSuccess("修改成功")
            } else {
                try await store.accountInsert(id: id, account: name, password: password)
                app.toastSuccess("新增成功")
            }
            onSuccess()
        } catch {
            app.toast(error, fallback: "提交失败")
        }
    }
}
