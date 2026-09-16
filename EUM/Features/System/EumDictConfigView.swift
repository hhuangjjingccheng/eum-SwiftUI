import SwiftUI

// MARK: - 字典管理（类型 + 字典数据）

struct EumDictView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var dictName = ""
    @State private var dictType = ""
    @State private var status: Int?
    @State private var page = 1
    @State private var pageSize = 10
    @State private var total = 0
    @State private var rows: [SysDictType] = []
    @State private var loading = false
    @State private var hasMore = false
    @State private var selected: Set<Int> = []
    @State private var tabs: [DynTab] = []
    @State private var active = "list"
    @State private var showBatchDelete = false
    @State private var typeCache: [Int: SysDictType] = [:]
    @State private var showFilter = false
    @State private var mobileForm: MobileTarget?

    enum MobileTarget: Identifiable {
        case add, detail(SysDictType), edit(SysDictType), dataList(SysDictType)
        var id: String {
            switch self {
            case .add: return "add"
            case .detail(let t): return "detail-\(t.id)"
            case .edit(let t): return "edit-\(t.id)"
            case .dataList(let t): return "data-\(t.id)"
            }
        }
        var title: String {
            switch self {
            case .add: return "新增字典类型"
            case .detail(let t): return "详情 - \(t.dictName)"
            case .edit(let t): return "编辑 - \(t.dictName)"
            case .dataList(let t): return "字典数据 - \(t.dictName)"
            }
        }
    }

    private var isCompact: Bool { hSize == .compact }

    private var columns: [TableCol] = [
        .init(L("eum.dict.read.dictName")),
        .init(L("eum.dict.read.dictType"), 170),
        .init(L("eum.status"), 70, align: .center),
        .init(L("eum.remark")),
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
                MobileSearchBar(text: $dictName,
                                placeholder: String(format: L("common.searchFormat"), L("eum.dict.read.dictName")),
                                filterCount: (dictType.isEmpty ? 0 : 1) + (status == nil ? 0 : 1),
                                onFilter: { showFilter = true },
                                onSubmit: { page = 1; Task { await load() } })
                FilterChipsBar(chips: filterChips, onClearAll: {
                    dictType = ""; status = nil
                    page = 1
                    Task { await load() }
                })
            } else {
                QueryForm {
                    QueryField(label: L("eum.dict.read.dictName"), text: $dictName)
                    QueryField(label: L("eum.dict.read.dictType"), text: $dictType)
                    QueryPickerField(label: L("eum.status"), value: $status, options: DictOption.eumStatus)
                } onSearch: {
                    page = 1
                    Task { await load() }
                } onReset: {
                    dictName = ""; dictType = ""; status = nil
                    page = 1
                    Task { await load() }
                }
                DynTabBar(tabs: $tabs, active: $active, fixedTitle: L("list.dicts"))
            }
        }
    }

    private var filterChips: [MobileFilterChip] {
        var chips: [MobileFilterChip] = []
        if !dictType.isEmpty {
            chips.append(.init(id: "type", label: "类型：\(dictType)", onRemove: {
                dictType = ""
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
            Group {
                switch target {
                case .add:
                    MobileSheetContainer(title: target.title) {
                        DictFormView(onClose: { mobileForm = nil }) {
                            mobileForm = nil
                            Task { await load() }
                        }
                    }
                case .edit(let type):
                    MobileSheetContainer(title: target.title) {
                        DictFormView(dictType: type, onClose: { mobileForm = nil }) {
                            mobileForm = nil
                            Task { await load() }
                        }
                    }
                case .detail(let type):
                    MobileSheetContainer(title: target.title) {
                        DictDetailView(dictType: type, onClose: { mobileForm = nil })
                    }
                case .dataList(let type):
                    DictDataListTab(dictType: type, onClose: { mobileForm = nil })
                        .environmentObject(app)
                        .environmentObject(store)
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

    private func mobileCard(for item: SysDictType) -> MobileCardModel {
        MobileCardModel(
            id: item.id,
            title: item.dictName,
            subtitle: item.dictType,
            initials: String(item.dictName.prefix(1)),
            showBadge: true,
            badgeText: item.status == 1 ? L("eum.status.enable") : L("eum.status.disable"),
            badgeKind: item.status == 1 ? .success : .danger,
            fields: [
                .init(label: L("eum.remark"), value: item.remark.isEmpty ? "-" : item.remark),
            ],
            actions: [
                .init(title: L("dict.data")) { mobileForm = .dataList(item) },
                .init(title: L("button.detail")) { mobileForm = .detail(item) },
                .init(title: L("button.edit")) { mobileForm = .edit(item) },
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
                        Text("字典类型")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                        TextField("请输入字典类型", text: $dictType)
                            .font(.system(size: 13))
                            .textInputAutocapitalization(.never)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(Theme.panelBG)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                    }
                    HStack(spacing: 10) {
                        WireButton(title: L("button.reset"), variant: .defaultPlain) {
                            dictType = ""
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
        let item = rows[idx]
        return HStack(spacing: 0) {
            TableCell(text: item.dictName)
            Button {
                typeCache[item.id] = item
                active = tabs.open(name: "dataList-\(item.id)", title: String(format: L("dict.dataTitle"), item.dictName))
            } label: {
                TableCell(text: item.dictType, width: 170, color: Theme.primary)
            }
            .buttonStyle(.plain)
            TableCell(text: Theme.statusText(item.status), width: 70, align: .center,
                      color: item.status == 1 ? Theme.success : Theme.danger)
            TableCell(text: item.remark.isEmpty ? "-" : item.remark)
            HStack(spacing: 10) {
                WireButton(title: L("button.detail"), icon: "book", variant: .linkPrimary, small: true) {
                    typeCache[item.id] = item
                    active = tabs.open(name: "detail-\(item.id)", title: String(format: L("tab.detail"), item.dictName))
                }
                WireButton(title: L("button.edit"), icon: "pencil", variant: .linkPrimary, small: true) {
                    typeCache[item.id] = item
                    active = tabs.open(name: "edit-\(item.id)", title: String(format: L("tab.edit"), item.dictName))
                }
            }
            .frame(width: 130, alignment: .center)
        }
    }

    @ViewBuilder
    private var tabSections: some View {
        ForEach(tabs) { tab in
            if active == tab.name {
                if tab.name.hasPrefix("dataList-") {
                    let id = Int(tab.name.replacingOccurrences(of: "dataList-", with: "")) ?? 0
                    if let type = typeCache[id] ?? rows.first(where: { $0.id == id }) {
                        DictDataListTab(dictType: type, onClose: { closeTab(tab.name) })
                    }
                } else if tab.name.hasPrefix("add-") {
                    WireCard(fullHeight: true) {
                        DictFormView(onClose: { closeTab(tab.name) }) {
                            closeTab(tab.name)
                            Task { await load() }
                        }
                    }
                } else if tab.name.hasPrefix("edit-") {
                    let id = Int(tab.name.replacingOccurrences(of: "edit-", with: "")) ?? 0
                    if let type = typeCache[id] ?? rows.first(where: { $0.id == id }) {
                        WireCard(fullHeight: true) {
                            DictFormView(dictType: type, onClose: { closeTab(tab.name) }) {
                                closeTab(tab.name)
                                Task { await load() }
                            }
                        }
                    }
                } else if tab.name.hasPrefix("detail-") {
                    let id = Int(tab.name.replacingOccurrences(of: "detail-", with: "")) ?? 0
                    if let type = typeCache[id] ?? rows.first(where: { $0.id == id }) {
                        WireCard(fullHeight: true) {
                            DictDetailView(dictType: type, onClose: { closeTab(tab.name) })
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
            let r = try await store.dictTypePage(page: page, size: pageSize, dictName: dictName, dictType: dictType, status: status)
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

    private func doBatchDelete() async {
        do {
            try await store.dictTypeDelete(ids: Array(selected))
            app.toastSuccess("删除成功")
        } catch {
            app.toast(error, fallback: "删除失败")
        }
        selected.removeAll()
        await load()
    }
}

// MARK: - 字典类型表单 / 详情

struct DictFormView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    var dictType: SysDictType? = nil
    var onClose: () -> Void
    var onSuccess: () -> Void

    @State private var form = SysDictType(id: 0, dictName: "", dictType: "")
    @State private var loading = false
    private var isEdit: Bool { dictType != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(isEdit ? "编辑字典" : "新增字典")
                    .font(.system(size: 16, weight: .semibold))
                FormTextField(label: L("eum.dict.read.dictName"), required: true, placeholder: "请输入字典名称", text: $form.dictName)
                FormTextField(label: L("eum.dict.read.dictType"), required: true, placeholder: "请输入字典类型", text: $form.dictType)
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
            if let dictType { form = dictType }
        }
        /// §4.32 编辑时按 ID 拉取详情（对齐 detail 接口）
        .task {
            guard let dictType else { return }
            if let detail = try? await store.dictTypeDetail(id: dictType.id) {
                form = detail
            }
        }
    }

    private func submit() async {
        guard !form.dictName.isEmpty else { app.toastError("字典名称不能为空"); return }
        guard !form.dictType.isEmpty else { app.toastError("字典类型不能为空"); return }
        loading = true
        defer { loading = false }
        do {
            if isEdit {
                try await store.dictTypeUpdate(form)
                app.toastSuccess("修改成功")
            } else {
                try await store.dictTypeInsert(form)
                app.toastSuccess("新增成功")
            }
            onSuccess()
        } catch {
            app.toast(error, fallback: "提交失败")
        }
    }
}

struct DictDetailView: View {
    let dictType: SysDictType
    var onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("字典详情")
                    .font(.system(size: 16, weight: .semibold))
                DetailGrid(items: [
                    .init(label: L("eum.dict.read.dictName"), value: dictType.dictName),
                    .init(label: L("eum.dict.read.dictType"), value: dictType.dictType),
                    .init(label: L("eum.status"), value: Theme.statusText(dictType.status)),
                    .init(label: L("eum.createTime"), value: dictType.createTime),
                    .init(label: L("eum.remark"), value: dictType.remark.isEmpty ? "-" : dictType.remark, span2: true),
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

// MARK: - 字典数据列表（tab 内完整列表页）

struct DictDataListTab: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    let dictType: SysDictType
    var onClose: () -> Void

    @State private var dictLabel = ""
    @State private var page = 1
    @State private var pageSize = 10
    @State private var selected: Set<Int> = []
    @State private var showAdd = false
    @State private var editing: SysDictData?
    @State private var showBatchDelete = false

    @State private var total = 0
    @State private var rows: [SysDictData] = []
    @State private var loading = false

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let r = try await store.dictDataPage(page: page, size: pageSize, typeId: dictType.id, dictLabel: dictLabel)
            rows = r.content
            total = r.total
            selected.removeAll()
        } catch {
            app.toast(error, fallback: "加载失败")
        }
    }

    private var columns: [TableCol] = [
        .init(L("eum.dict.data.read.dictLabel"), 120),
        .init(L("eum.dict.data.read.dictValue"), 100),
        .init(L("eum.dict.data.read.i18nKey"), 130),
        .init(L("eum.sort"), 50, align: .center),
        .init(L("eum.status"), 70, align: .center),
        .init(L("eum.remark")),
        .init(L("eum.operation"), 110, align: .center),
    ]

    var body: some View {
        VStack(spacing: 8) {
            QueryForm {
                QueryField(label: L("eum.dict.data.read.dictLabel"), text: $dictLabel)
            } onSearch: {
                page = 1
                Task { await load() }
            } onReset: {
                dictLabel = ""
                page = 1
                Task { await load() }
            }

            WireCard(fullHeight: true) {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        WireButton(title: L("button.add"), icon: "add-circle", variant: .primary, small: true) {
                            showAdd = true
                        }
                        WireButton(title: L("button.batchDelete"), icon: "delete", variant: .danger, small: true, disabled: selected.isEmpty) {
                            showBatchDelete = true
                        }
                        Spacer()
                        WireButton(title: L("button.close"), icon: "close-circle", variant: .ghost, small: true, action: onClose)
                    }
                    .padding(10)

                    WireTable(columns: columns, rowCount: rows.count, selectable: true, selection: selectedIndexes()) { idx in
                        let id = rows[idx].id
                        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
                    } rowAction: { idx in
                        row(idx)
                    }

                    PaginationBar(total: total, page: $page, pageSize: $pageSize) { Task { await load() } }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            DictDataFormView(dictType: dictType, existing: nil) {
                Task { await load() }
            }
            .environmentObject(app)
            .environmentObject(store)
        }
        .sheet(item: $editing) { data in
            DictDataFormView(dictType: dictType, existing: data) {
                Task { await load() }
            }
            .environmentObject(app)
            .environmentObject(store)
        }
        .confirmationDialog(String(format: L("common.confirmDelete"), selected.count), isPresented: $showBatchDelete, titleVisibility: .visible) {
            Button(L("button.delete"), role: .destructive) {
                Task {
                    do {
                        try await store.dictDataDelete(ids: Array(selected))
                        app.toastSuccess("删除成功")
                    } catch {
                        app.toast(error, fallback: "删除失败")
                    }
                    selected.removeAll()
                    await load()
                }
            }
            Button(L("button.cancel"), role: .cancel) {}
        }
        .task { await load() }
        .overlay { TableLoadingOverlay(loading: loading) }
    }

    private func row(_ idx: Int) -> some View {
        let data = rows[idx]
        return HStack(spacing: 0) {
            TableCell(text: data.dictLabel, width: 120)
            TableCell(text: data.dictValue, width: 100)
            TableCell(text: data.i18nKey.isEmpty ? "-" : data.i18nKey, width: 130, mono: true, color: Theme.textSecondary)
            TableCell(text: "\(data.dictSort)", width: 50, align: .center, color: Theme.textSecondary)
            TableCell(text: Theme.statusText(data.status), width: 70, align: .center,
                      color: data.status == 1 ? Theme.success : Theme.danger)
            TableCell(text: data.remark.isEmpty ? "-" : data.remark)
            HStack(spacing: 8) {
                WireButton(title: L("button.edit"), icon: "pencil", variant: .linkPrimary, small: true) {
                    editing = data
                }
                WireButton(title: L("button.delete"), icon: "delete", variant: .linkDanger, small: true) {
                    Task {
                        do {
                            try await store.dictDataDelete(ids: [data.id])
                            app.toastSuccess("删除成功")
                            await load()
                        } catch {
                            app.toast(error, fallback: "删除失败")
                        }
                    }
                }
            }
            .frame(width: 110, alignment: .center)
        }
    }

    private func selectedIndexes() -> Set<Int> {
        Set(rows.enumerated().compactMap { selected.contains($0.element.id) ? $0.offset : nil })
    }
}

// MARK: - 字典数据表单

struct DictDataFormView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    let dictType: SysDictType
    var existing: SysDictData?
    var onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var form = SysDictData(id: 0, typeId: 0, dictLabel: "", dictValue: "")
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        FormFieldLabel(text: L("eum.dict.read.dictType"))
                        Text(dictType.dictType)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textSecondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 7)
                            .background(Theme.pageBG)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                    }
                    FormTextField(label: L("eum.dict.data.read.dictLabel"), required: true, placeholder: "请输入字典标签", text: $form.dictLabel)
                    FormTextField(label: L("eum.dict.data.read.dictValue"), required: true, placeholder: "请输入字典键值", text: $form.dictValue)
                    FormTextField(label: L("eum.dict.data.read.i18nKey"), placeholder: "请输入国际化键", text: $form.i18nKey)
                    FormNumberField(label: "字典排序", required: true, value: $form.dictSort)
                    FormRadioRow(label: "状态", options: [(1, "启用"), (0, "停用")], value: $form.status)
                    FormTextareaField(label: L("eum.remark"), placeholder: String(format: L("eum.placeholder.inputFormat"), L("eum.remark")), text: $form.remark)

                    FormActions(loading: loading) {
                        dismiss()
                    } onConfirm: {
                        Task { await submit() }
                    }
                }
                .padding(20)
            }
            .navigationTitle(existing == nil ? "新增字典数据" : "编辑字典数据")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            if let existing {
                form = existing
            } else {
                form.typeId = dictType.id
            }
        }
        /// §4.31 编辑时按 ID 拉取详情
        .task {
            guard let existing else { return }
            if let detail = try? await store.dictDataDetail(id: existing.id) {
                form = detail
            }
        }
    }

    private func submit() async {
        guard !form.dictLabel.isEmpty else { app.toastError("字典标签不能为空"); return }
        guard !form.dictValue.isEmpty else { app.toastError("字典键值不能为空"); return }
        form.typeId = dictType.id
        loading = true
        defer { loading = false }
        do {
            if existing != nil {
                try await store.dictDataUpdate(form)
                app.toastSuccess("修改成功")
            } else {
                try await store.dictDataInsert(form)
                app.toastSuccess("新增成功")
            }
            onSuccess()
            dismiss()
        } catch {
            app.toast(error, fallback: "提交失败")
        }
    }
}

// MARK: - 参数设置（系统全局配置）

struct EumConfigView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    @Environment(\.horizontalSizeClass) private var hSize

    private var isCompact: Bool { hSize == .compact }

    @State private var themeColor = "#409EFF"
    @State private var apiKeyId: Int?
    @State private var language = "zh-CN"
    @State private var mode = "visual"   // visual / json
    @State private var jsonText = "{}"
    @State private var searchKey = ""
    @State private var showAddLanguage = false
    @State private var newLanguage = ""
    @State private var languageError = ""
    @State private var saving = false
    @State private var loading = false
    @State private var switchingLanguage = false

    /// 主题色预设（对齐 web 端；首个为线框默认黑）
    private static let themePresets: [(hex: String, name: String)] = [
        ("#171717", "config.theme.preset.black"),
        ("#409EFF", "config.theme.preset.blue"),
        ("#1E6FFF", "config.theme.preset.brand"),
        ("#67C23A", "config.theme.preset.green"),
        ("#E6A23C", "config.theme.preset.orange"),
        ("#F56C6C", "config.theme.preset.red"),
        ("#6366F1", "config.theme.preset.indigo"),
    ]

    private var languages: [String] {
        Array(store.sysConfig.languageJson.keys).sorted()
    }

    private var langTable: [String: [String: String]] {
        store.sysConfig.languageJson.compactMapValues { $0 as? [String: String] }
    }

    private var visualKeys: [String] {
        var keys = Set<String>()
        for (_, dict) in langTable { keys.formUnion(dict.keys) }
        return keys.sorted()
    }

    private var filteredKeys: [String] {
        visualKeys.filter { searchKey.isEmpty || $0.localizedCaseInsensitiveContains(searchKey) }
    }

    /// 语言选项：跟随系统 + languageJson 已配置语言
    private var languageOptions: [(code: String, label: String)] {
        [("system", L("config.lang.system"))] + I18n.availableLanguages.map { ($0, Self.languageLabel($0)) }
    }

    private static func languageLabel(_ code: String) -> String {
        switch code {
        case "zh-CN": return L("lang.zh-CN")
        case "en": return L("lang.en")
        case "ja": return L("lang.ja")
        default: return code
        }
    }

    private static func isDark(_ hex: String) -> Bool {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        let r = Double((v >> 16) & 0xFF), g = Double((v >> 8) & 0xFF), b = Double(v & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) < 140
    }

    /// 选中密钥解析详情（保存写入 sys/config 后由服务端 chat/stream 使用）
    private var selectedKey: AIApiKey? {
        store.apiKeys.first { $0.id == apiKeyId }
    }

    var body: some View {
        PageLayout(header: WirePageHeader(title: L("config.title"), description: L("config.subtitle"))) {
            if isCompact {
                // 手机端：分区卡片
                VStack(spacing: Theme.gap) {
                    WireCard { themeSection.padding(14) }
                    WireCard { aiSection.padding(14) }
                    WireCard { languageSection.padding(14) }
                    WireCard(title: "多语言高级配置") { advancedSection.padding(14) }
                }
            } else {
                // iPad / Mac：单卡分区
                WireCard(title: L("config.title")) {
                    VStack(alignment: .leading, spacing: 18) {
                        themeSection
                        Divider()
                        aiSection
                        Divider()
                        languageSection
                        Divider()
                        advancedSection
                    }
                    .padding(16)
                }
            }
        }
        .overlay { TableLoadingOverlay(loading: loading) }
        .overlay {
            if switchingLanguage {
                languageSwitchingOverlay
            }
        }
        .animation(.easeInOut(duration: 0.2), value: switchingLanguage)
        .task { await load() }
        // 离开页面时还原为已保存的主题色（未保存的预览色不落盘）
        .onDisappear { Theme.applyThemeColor(store.sysConfig.themeColor) }
        .alert(L("config.alert.addLang"), isPresented: $showAddLanguage) {
            TextField(L("config.alert.langPlaceholder"), text: $newLanguage)
            Button(L("button.confirm")) { addLanguage() }
            Button(L("button.cancel"), role: .cancel) {}
        } message: {
            Text(languageError.isEmpty ? L("config.alert.bcp47") : languageError)
        }
    }

    // MARK: 主题色（点选即时预览，保存写入 themeColor 全局生效）

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L("eum.tone"), subtitle: L("config.theme.subtitle"))
            HStack(spacing: isCompact ? 14 : 12) {
                ForEach(Self.themePresets, id: \.hex) { preset in
                    let isSelected = themeColor == preset.hex
                    Button {
                        themeColor = preset.hex
                        Theme.applyThemeColor(preset.hex)
                    } label: {
                        VStack(spacing: 5) {
                            Circle()
                                .fill(Color(hexString: preset.hex))
                                .frame(width: isCompact ? 32 : 28, height: isCompact ? 32 : 28)
                                .overlay(
                                    Circle().stroke(isSelected ? Theme.text : Theme.border, lineWidth: isSelected ? 2 : 1)
                                )
                                .overlay {
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(Self.isDark(preset.hex) ? .white : Theme.text)
                                    }
                                }
                            Text(L(preset.name))
                                .font(.system(size: 10))
                                .foregroundColor(isSelected ? Theme.text : Theme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(L("config.theme.current") + themeColor)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
        }
    }

    // MARK: AI 助手密钥（写入 eumEumAiApiKey，服务端 chat/stream 按此转发）

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L("eum.ai.assistant.apiKey"), subtitle: L("config.ai.subtitle"))
            Picker("AI 助手的 APIKey", selection: $apiKeyId) {
                Text(L("eum.placeholder.select")).tag(Int?.none)
                ForEach(store.apiKeys) { key in
                    Text("\(store.providerName(key.providerId)) · \(key.apiKeyPrefix)").tag(Int?.some(key.id))
                }
            }
            .pickerStyle(.menu)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
            if let key = selectedKey {
                HStack(spacing: 6) {
                    StatusTag(text: store.providerName(key.providerId), kind: .primary)
                    StatusTag(text: L("config.ai.keyPrefix") + " \(key.apiKeyPrefix)···", kind: .mono)
                    if !key.defaultModel.isEmpty {
                        StatusTag(text: L("config.ai.defaultModel") + " \(key.defaultModel)", kind: .info)
                    }
                    StatusTag(text: String(format: L("config.ai.models"), key.models.count), kind: .mono)
                }
            } else if store.apiKeys.isEmpty {
                Text(L("config.ai.noKeys"))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            } else {
                Text(L("config.ai.noSelection"))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }
        }
    }

    // MARK: 界面语言（写入 language，保存后翻译表与菜单立即生效）

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L("eum.language"), subtitle: L("config.lang.subtitle"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: isCompact ? 108 : 128), spacing: 8)], spacing: 8) {
                ForEach(languageOptions, id: \.code) { option in
                    let isSelected = option.code == "system" ? language == "system" : language == option.code
                    Button {
                        Task { await switchLanguage(to: option.code) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 12))
                                .foregroundColor(isSelected ? Theme.primary : Theme.textTertiary)
                            Text(option.label)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                .foregroundColor(Theme.text)
                                .lineLimit(1)
                            if option.code == "system", language == "system" {
                                Text("(" + I18n.resolve("system", available: languages) + ")")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.textTertiary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isSelected ? Theme.primaryLight9 : Theme.panelBG)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Theme.primary : Theme.border, lineWidth: 1))
                        .clipShape(RoundedCorner(radius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .disabled(switchingLanguage)
        }
    }

    /// 语言切换转场：整页遮罩 + 转圈，完成后新语言文案填充
    private var languageSwitchingOverlay: some View {
        ZStack {
            Theme.pageBG.opacity(0.8)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(1.1)
                Text(L("config.lang.switching"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.text)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(Theme.panelBG)
            .clipShape(RoundedCorner(radius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
            .panelShadow()
        }
        .transition(.opacity)
    }

    // MARK: 多语言高级配置（languageJson：可视化 / JSON 双模式）

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("config.adv.title"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                Picker("模式", selection: $mode) {
                    Text(L("eum.visualization")).tag("visual")
                    Text(L("config.adv.json")).tag("json")
                }
                .pickerStyle(.segmented)
                .frame(width: isCompact ? 150 : 180)
            }

            if mode == "visual" {
                if isCompact {
                    visualEditorCompact
                } else {
                    visualEditor
                }
            } else {
                TextEditor(text: $jsonText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: isCompact ? 200 : 240)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(Theme.pageBG)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
            }

            HStack(spacing: 10) {
                WireButton(title: L("eum.addWord"), icon: "add-circle", variant: .defaultPlain, small: true) {
                    addWord()
                }
                WireButton(title: L("eum.addLanguage"), icon: "add", variant: .defaultPlain, small: true) {
                    newLanguage = ""; languageError = ""
                    showAddLanguage = true
                }
                Spacer()
                WireButton(title: L("eum.save"), variant: .primary, small: true, loading: saving) {
                    Task { await save() }
                }
            }
        }
    }

    /// 手机端词条编辑：一键一行（多语言宽表在窄屏放不下）
    private var visualEditorCompact: some View {
        VStack(alignment: .leading, spacing: 8) {
            MobileSearchBar(text: $searchKey, placeholder: L("config.adv.searchKey"), onFilter: {}, onSubmit: {})
            ForEach(filteredKeys, id: \.self) { key in
                VStack(alignment: .leading, spacing: 6) {
                    Text(key)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.text)
                    ForEach(languages, id: \.self) { lang in
                        HStack(spacing: 8) {
                            Text(lang)
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textSecondary)
                                .frame(width: 60, alignment: .leading)
                            TextField(L("config.adv.textLabel"), text: visualValue(lang: lang, key: key))
                                .font(.system(size: 12))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Theme.pageBG)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                        }
                    }
                }
                .padding(10)
                .background(Theme.pageBG.opacity(0.4))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 1))
                .clipShape(RoundedCorner(radius: 6))
            }
            if filteredKeys.isEmpty {
                Text(visualKeys.isEmpty ? L("config.empty.words") : L("config.empty.noMatch"))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.text)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        async let cfgTask: Void = store.loadSysConfig()
        async let keysTask: Void = store.loadApiKeys()
        _ = await (cfgTask, keysTask)
        let cfg = store.sysConfig
        themeColor = cfg.themeColor
        apiKeyId = cfg.assistantApiKeyId
        language = cfg.language
        if let data = try? JSONSerialization.data(withJSONObject: cfg.languageJson, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            jsonText = text
        }
    }

    private func addWord() {
        let key = searchKey.isEmpty ? "menu.new\(Int(Date().timeIntervalSince1970))" : searchKey
        var json = store.sysConfig.languageJson
        for lang in languages {
            var dict = json[lang] as? [String: String] ?? [:]
            dict[key] = ""
            json[lang] = dict
        }
        store.sysConfig.languageJson = json
        if mode == "json" { syncJsonFromVisual() }
        app.toastSuccess(String(format: L("config.toast.wordAdded"), key))
    }

    private func addLanguage() {
        let pattern = "^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2})?$"
        guard newLanguage.range(of: pattern, options: .regularExpression) != nil else {
            languageError = L("config.alert.bcp47Error")
            showAddLanguage = true
            return
        }
        var json = store.sysConfig.languageJson
        json[newLanguage] = [String: String]()
        store.sysConfig.languageJson = json
        language = newLanguage
        if mode == "json" { syncJsonFromVisual() }
        app.toastSuccess(String(format: L("config.toast.langAdded"), newLanguage))
    }

    private func deleteLanguage(_ lang: String) {
        guard languages.count > 1 else { return }
        var json = store.sysConfig.languageJson
        json.removeValue(forKey: lang)
        store.sysConfig.languageJson = json
        if language == lang { language = "zh-CN" }
        if mode == "json" { syncJsonFromVisual() }
    }

    private func visualValue(lang: String, key: String) -> Binding<String> {
        Binding(
            get: { langTable[lang]?[key] ?? "" },
            set: { v in
                var json = store.sysConfig.languageJson
                var dict = json[lang] as? [String: String] ?? [:]
                dict[key] = v
                json[lang] = dict
                store.sysConfig.languageJson = json
            }
        )
    }

    private func syncJsonFromVisual() {
        if let data = try? JSONSerialization.data(withJSONObject: store.sysConfig.languageJson, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            jsonText = text
        }
    }

    private var visualEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            QueryField(label: L("eum.translateLable"), text: $searchKey)

            // 表头
            HStack(spacing: 0) {
                Text(L("eum.translateLable")).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                    .frame(width: 140, alignment: .leading).padding(.horizontal, 8)
                ForEach(languages, id: \.self) { lang in
                    HStack(spacing: 4) {
                        Text(lang).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                        if lang == language {
                            StatusTag(text: L("config.adv.default"), kind: .primary)
                        }
                        if languages.count > 1 {
                            Button {
                                deleteLanguage(lang)
                            } label: {
                                Text(L("common.delete")).font(.system(size: 11)).foregroundColor(Color(hex: 0xFCA5A5))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            }
            .padding(.vertical, 8)
            .background(Theme.tableHeaderBG)
            .clipShape(RoundedCorner(radius: 3))

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(visualKeys.filter { searchKey.isEmpty || $0.localizedCaseInsensitiveContains(searchKey) }, id: \.self) { key in
                        HStack(spacing: 0) {
                            Text(key)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Theme.text)
                                .frame(width: 140, alignment: .leading)
                                .padding(.horizontal, 8)
                            ForEach(languages, id: \.self) { lang in
                                TextField(L("config.adv.textLabel"), text: visualValue(lang: lang, key: key))
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(Theme.pageBG)
                                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.border, lineWidth: 1))
                                    .padding(.horizontal, 4)
                            }
                        }
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderLight).frame(height: 1) }
                    }
                }
            }
            .frame(maxHeight: 320)
        }
    }

    /// 点击语言选项 → 转圈 → 新语言填充 → 持久化（失败回滚并提示）
    private func switchLanguage(to code: String) async {
        let previous = language
        guard code != previous, !switchingLanguage else { return }
        switchingLanguage = true
        defer { switchingLanguage = false }
        // 1) 让转场可感知：短暂停留后执行切换
        try? await Task.sleep(nanoseconds: 550_000_000)
        // 2) 本地立即生效：翻译表 + Accept-Language + 全局取词刷新
        language = code
        var cfg = store.sysConfig
        cfg.language = code
        I18n.apply(languageJson: cfg.languageJson, language: code)
        APIClient.shared.language = I18n.language
        app.i18nVersion += 1
        // 3) 持久化到 sys/config；失败回滚到原语言
        do {
            try await store.saveSysConfig(cfg)
            store.sysConfig = cfg
            app.toastSuccess(L("config.toast.langSwitched"))
        } catch {
            language = previous
            I18n.apply(languageJson: store.sysConfig.languageJson, language: previous)
            app.i18nVersion += 1
            app.toast(error, fallback: L("config.error.save"))
        }
    }

    private func save() async {
        var cfg = store.sysConfig
        cfg.themeColor = themeColor
        cfg.assistantApiKeyId = apiKeyId
        cfg.language = language
        if mode == "json" {
            guard let data = jsonText.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data),
                  let parsed = obj as? [String: Any] else {
                app.toastError(L("config.toast.jsonError"))
                return
            }
            cfg.languageJson = parsed
        }
        saving = true
        defer { saving = false }
        do {
            try await store.saveSysConfig(cfg)
            store.sysConfig = cfg
            // 配置即时生效：
            // 1) themeColor → 全局主操作色  2) languageJson → I18n 取词表
            // 3) language（"system" 解析为具体码）→ Accept-Language  4) 重建侧边栏/页签重新取词
            Theme.applyThemeColor(cfg.themeColor)
            I18n.apply(languageJson: cfg.languageJson, language: cfg.language)
            APIClient.shared.language = I18n.language
            app.i18nVersion += 1
            app.toastSuccess(L("config.toast.saved"))
        } catch {
            app.toast(error, fallback: L("config.error.save"))
        }
    }
}
