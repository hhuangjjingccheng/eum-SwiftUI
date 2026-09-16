import SwiftUI

// MARK: - FXShell 异常管理（bovinishell）

struct FxshellView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var platform = ""
    @State private var email = ""
    @State private var repair: Int?
    @State private var page = 1
    @State private var pageSize = 10
    @State private var total = 0
    @State private var rows: [FxshellLog] = []
    @State private var loading = false
    @State private var hasMore = false
    @State private var selected: Set<Int> = []
    @State private var showBatchDelete = false
    @State private var tabs: [DynTab] = []
    @State private var active = "list"
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
            case .add: return "新增异常记录"
            case .detail: return "异常详情"
            case .edit: return "编辑异常记录"
            }
        }
    }

    private var isCompact: Bool { hSize == .compact }

    private let repairOptions: [DictOption] = [
        .init(label: L("fxshell.unrepaired"), value: 0, kind: .warning),
        .init(label: L("fxshell.repaired"), value: 1, kind: .success),
    ]

    private var columns: [TableCol] = [
        .init(L("eum.index"), 60, align: .center),
        .init(L("fxshell.errorLog"), 260),
        .init(L("fxshell.platform"), 110),
        .init(L("fxshell.repaired"), 90, align: .center),
        .init(L("eum.user.read.email"), 180),
        .init(L("eum.createTime"), 160),
        .init(L("eum.operation"), 130, align: .center),
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
                MobileSearchBar(text: $platform,
                                placeholder: String(format: L("common.searchFormat"), L("fxshell.platform")),
                                filterCount: (email.isEmpty ? 0 : 1) + (repair == nil ? 0 : 1),
                                onFilter: { showFilter = true },
                                onSubmit: { page = 1; Task { await load() } })
                FilterChipsBar(chips: filterChips, onClearAll: {
                    email = ""; repair = nil
                    page = 1
                    Task { await load() }
                })
            } else {
                QueryForm {
                    QueryField(label: L("fxshell.platform"), text: $platform)
                    QueryField(label: L("eum.user.read.email"), text: $email)
                    QueryPickerField(label: L("fxshell.repaired"), value: $repair, options: repairOptions)
                } onSearch: {
                    page = 1
                    Task { await load() }
                } onReset: {
                    platform = ""; email = ""; repair = nil
                    page = 1
                    Task { await load() }
                }
                DynTabBar(tabs: $tabs, active: $active, fixedTitle: L("list.fxshell"))
            }
        }
    }

    private var filterChips: [MobileFilterChip] {
        var chips: [MobileFilterChip] = []
        if !email.isEmpty {
            chips.append(.init(id: "email", label: "邮箱：\(email)", onRemove: {
                email = ""
                page = 1
                Task { await load() }
            }))
        }
        if let repair {
            chips.append(.init(id: "repair", label: repairOptions.first { $0.value == repair }?.label ?? "\(repair)", onRemove: {
                self.repair = nil
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
                    FxshellFormView(onClose: { mobileForm = nil }) {
                        mobileForm = nil
                        Task { await load() }
                    }
                case .edit(let id):
                    if let log = rows.first(where: { $0.id == id }) {
                        FxshellFormView(log: log, onClose: { mobileForm = nil }) {
                            mobileForm = nil
                            Task { await load() }
                        }
                    }
                case .detail(let id):
                    if let log = rows.first(where: { $0.id == id }) {
                        FxshellDetailView(log: log, onClose: { mobileForm = nil })
                    }
                }
            }
        }
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

    private func mobileCard(for log: FxshellLog) -> MobileCardModel {
        MobileCardModel(
            id: log.id,
            title: "#\(log.id) · \(log.platform.isEmpty ? "未知平台" : log.platform)",
            subtitle: log.email.isEmpty ? "未留邮箱" : log.email,
            showBadge: true,
            badgeText: log.repairText,
            badgeKind: log.repairKind,
            fields: [
                .init(label: L("eum.createTime"), value: String(log.createTime.prefix(19))),
                .init(label: L("eum.updateTime"), value: log.updateTime.isEmpty ? "-" : String(log.updateTime.prefix(19))),
            ],
            actions: [
                .init(title: L("button.detail")) { mobileForm = .detail(log.id) },
                .init(title: L("fxshell.markRepaired")) {
                    var copy = log
                    copy.isRepair = "1"
                    Task {
                        do {
                            try await store.fxshellUpdate(copy)
                            app.toastSuccess("已标记修复")
                            await load()
                        } catch {
                            app.toast(error, fallback: "操作失败")
                        }
                    }
                },
                .init(title: L("button.edit")) { mobileForm = .edit(log.id) },
            ]
        )
    }

    /// 手机端筛选弹层
    private var filterSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("是否修复")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                        HStack(spacing: 8) {
                            ForEach(repairOptions) { opt in
                                Button {
                                    repair = repair == opt.value ? nil : opt.value
                                } label: {
                                    Text(opt.label)
                                        .font(.system(size: 13))
                                        .foregroundColor(repair == opt.value ? .white : Theme.text)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .background(repair == opt.value ? Theme.primary : Theme.panelBG)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(repair == opt.value ? Theme.primary : Theme.border, lineWidth: 1)
                                        )
                                        .clipShape(RoundedCorner(radius: 8))
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("联系邮箱")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                        TextField("请输入邮箱", text: $email)
                            .font(.system(size: 13))
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(Theme.panelBG)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                    }
                    HStack(spacing: 10) {
                        WireButton(title: L("button.reset"), variant: .defaultPlain) {
                            email = ""
                            repair = nil
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

    private var toolbar: some View {
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
    }

    private func row(_ idx: Int) -> some View {
        let log = rows[idx]
        return HStack(spacing: 0) {
            TableCell(text: "\(idx + 1 + (page - 1) * pageSize)", width: 60, align: .center, color: Theme.textSecondary)
            TableCell(text: log.errorLog, width: 260)
            TableCell(text: log.platform.isEmpty ? "-" : log.platform, width: 110)
            HStack {
                StatusTag(text: log.repairText, kind: log.repairKind)
            }
            .frame(width: 90, alignment: .center)
            TableCell(text: log.email.isEmpty ? "-" : log.email, width: 180)
            TableCell(text: log.createTime, width: 160, color: Theme.textSecondary)
            HStack(spacing: 10) {
                WireButton(title: L("button.detail"), icon: "book", variant: .linkPrimary, small: true) {
                    active = tabs.open(name: "detail-\(log.id)", title: String(format: L("tab.detail"), "#" + String(log.id)))
                }
                WireButton(title: L("button.edit"), icon: "pencil", variant: .linkPrimary, small: true) {
                    active = tabs.open(name: "edit-\(log.id)", title: String(format: L("tab.edit"), "#" + String(log.id)))
                }
            }
            .frame(width: 130, alignment: .center)
        }
    }

    @ViewBuilder
    private var formAndDetailSections: some View {
        ForEach(tabs) { tab in
            if active == tab.name {
                WireCard(fullHeight: true) {
                    if tab.name.hasPrefix("add-") {
                        FxshellFormView(onClose: { closeTab(tab.name) }) {
                            closeTab(tab.name)
                            Task { await load() }
                        }
                    } else if tab.name.hasPrefix("edit-") {
                        let id = Int(tab.name.replacingOccurrences(of: "edit-", with: "")) ?? 0
                        if let log = rows.first(where: { $0.id == id }) {
                            FxshellFormView(log: log, onClose: { closeTab(tab.name) }) {
                                closeTab(tab.name)
                                Task { await load() }
                            }
                        }
                    } else if tab.name.hasPrefix("detail-") {
                        let id = Int(tab.name.replacingOccurrences(of: "detail-", with: "")) ?? 0
                        if let log = rows.first(where: { $0.id == id }) {
                            FxshellDetailView(log: log, onClose: { closeTab(tab.name) })
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
            let repairParam = repair.map(String.init) ?? ""
            let result = try await store.fxshellPage(page: page, size: pageSize,
                                                     platform: platform, isRepair: repairParam, email: email)
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
            try await store.fxshellDelete(ids: Array(selected))
            app.toastSuccess("删除成功")
            selected.removeAll()
        } catch {
            app.toast(error, fallback: "删除失败")
        }
        await load()
    }
}

// MARK: FXShell 表单

struct FxshellFormView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    var log: FxshellLog? = nil
    var onClose: () -> Void
    var onSuccess: () -> Void

    @State private var form = FxshellLog()
    @State private var loading = false

    private var isEdit: Bool { log != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(isEdit ? "编辑异常记录" : "新增异常记录")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text)

                FormTextField(label: L("fxshell.errorLog"), required: true, placeholder: "请输入错误日志", text: $form.errorLog)
                FormTextField(label: L("fxshell.platform"), placeholder: "如 macOS / Windows / iOS", text: $form.platform)
                FormTextField(label: L("biz.contactEmail"), placeholder: "用于修复后通知", text: $form.email)
                FormRadioRow(label: "是否修复", options: [(0, "未修复"), (1, "已修复")], value: Binding(
                    get: { form.isRepair == "1" ? 1 : 0 },
                    set: { form.isRepair = $0 == 1 ? "1" : "0" }
                ))

                FormActions(loading: loading) {
                    onClose()
                } onConfirm: {
                    Task { await submit() }
                }
            }
            .padding(20)
        }
        .onAppear {
            if let log { form = log }
        }
    }

    private func submit() async {
        guard !form.errorLog.isEmpty else { app.toastError("错误日志不能为空"); return }
        if !form.email.isEmpty, !form.email.contains("@") { app.toastError("邮箱格式不正确"); return }
        loading = true
        defer { loading = false }
        do {
            if isEdit {
                try await store.fxshellUpdate(form)
                app.toastSuccess("修改成功")
            } else {
                try await store.fxshellInsert(form)
                app.toastSuccess("新增成功")
            }
            onSuccess()
        } catch {
            app.toast(error, fallback: "提交失败")
        }
    }
}

// MARK: FXShell 详情

struct FxshellDetailView: View {
    let log: FxshellLog
    var onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("异常详情")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text)
                DetailGrid(items: [
                    .init(label: L("fxshell.recordNo"), value: "\(log.id)"),
                    .init(label: L("fxshell.platform"), value: log.platform.isEmpty ? "-" : log.platform),
                    .init(label: L("fxshell.repaired"), value: log.repairText),
                    .init(label: L("biz.contactEmail"), value: log.email.isEmpty ? "-" : log.email),
                    .init(label: L("eum.createTime"), value: log.createTime.isEmpty ? "-" : log.createTime),
                    .init(label: L("eum.updateTime"), value: log.updateTime.isEmpty ? "-" : log.updateTime),
                    .init(label: L("fxshell.errorLog"), value: log.errorLog, span2: true),
                ])
                HStack { Spacer(); WireButton(title: L("button.close"), variant: .defaultPlain, action: onClose) }
            }
            .padding(20)
        }
    }
}
