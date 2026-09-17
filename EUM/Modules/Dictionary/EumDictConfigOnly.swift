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
