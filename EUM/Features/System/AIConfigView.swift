import SwiftUI

// MARK: - AI 配置（三级：Provider → ApiKey → ApiKeyModel）

struct AIConfigView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    @Environment(\.horizontalSizeClass) private var hSize

    // 固定列表页签：provider / apikey / apikey-model
    @State private var active = "provider"
    @State private var tabs: [DynTab] = []

    // provider
    @State private var providerName = ""
    @State private var providerStatus: Int?
    @State private var providerPage = 1
    @State private var providerPageSize = 10
    @State private var providerTotal = 0
    @State private var providerRows: [AIProvider] = []
    @State private var providerSelected: Set<Int> = []

    // apikey
    @State private var apiKeyProvider: Int?
    @State private var apiKeyPage = 1
    @State private var apiKeyPageSize = 10
    @State private var apiKeyTotal = 0
    @State private var apiKeyRows: [AIApiKey] = []
    @State private var apiKeySelected: Set<Int> = []

    // apikey-model
    @State private var modelApiKey: Int?
    @State private var modelPage = 1
    @State private var modelPageSize = 10
    @State private var modelTotal = 0
    @State private var modelRows: [AIApiKeyModel] = []
    @State private var modelSelected: Set<Int> = []

    @State private var loading = false
    @State private var showBatchDelete = false
    @State private var providerHasMore = false
    @State private var keyHasMore = false
    @State private var modelHasMore = false
    @State private var mobileForm: MobileTarget?

    enum MobileTarget: Identifiable {
        case providerAdd, providerDetail(Int), providerEdit(Int)
        case keyAdd, keyDetail(Int), keyEdit(Int)
        case modelAdd, modelDetail(Int), modelEdit(Int)

        var id: String {
            switch self {
            case .providerAdd: return "p-add"
            case .providerDetail(let i): return "p-detail-\(i)"
            case .providerEdit(let i): return "p-edit-\(i)"
            case .keyAdd: return "k-add"
            case .keyDetail(let i): return "k-detail-\(i)"
            case .keyEdit(let i): return "k-edit-\(i)"
            case .modelAdd: return "m-add"
            case .modelDetail(let i): return "m-detail-\(i)"
            case .modelEdit(let i): return "m-edit-\(i)"
            }
        }

        var title: String {
            switch self {
            case .providerAdd: return "新增 AI 平台"
            case .providerDetail: return "平台详情"
            case .providerEdit: return "编辑 AI 平台"
            case .keyAdd: return "新增密钥"
            case .keyDetail: return "密钥详情"
            case .keyEdit: return "编辑密钥"
            case .modelAdd: return "新增模型关联"
            case .modelDetail: return "模型详情"
            case .modelEdit: return "编辑模型关联"
            }
        }
    }

    private var isCompact: Bool { hSize == .compact }

    var body: some View {
        PageLayout(header: headerSection, scrolls: !isCompact) {
            if active == "provider" {
                if isCompact { mobileProviderList } else { providerList }
            } else if active == "apikey" {
                if isCompact { mobileApiKeyList } else { apiKeyList }
            } else if active == "apikey-model" {
                if isCompact { mobileModelList } else { modelList }
            } else {
                dynTabSections
            }
        }
        .overlay { TableLoadingOverlay(loading: loading) }
        .sheet(item: $mobileForm) { target in
            MobileSheetContainer(title: target.title) {
                switch target {
                case .providerAdd:
                    ProviderFormView(onClose: { mobileForm = nil }) {
                        mobileForm = nil
                        Task { await loadProvider() }
                    }
                case .providerDetail(let id):
                    if let p = store.providers.first(where: { $0.id == id }) {
                        ProviderDetailView(provider: p, onClose: { mobileForm = nil })
                    }
                case .providerEdit(let id):
                    if let p = store.providers.first(where: { $0.id == id }) {
                        ProviderFormView(provider: p, onClose: { mobileForm = nil }) {
                            mobileForm = nil
                            Task { await loadProvider() }
                        }
                    }
                case .keyAdd:
                    ApiKeyFormView(onClose: { mobileForm = nil }) {
                        mobileForm = nil
                        Task { await loadApiKeys() }
                    }
                case .keyDetail(let id):
                    if let k = store.apiKeys.first(where: { $0.id == id }) {
                        ApiKeyDetailView(apiKey: k, onClose: { mobileForm = nil })
                    }
                case .keyEdit(let id):
                    if let k = store.apiKeys.first(where: { $0.id == id }) {
                        ApiKeyFormView(apiKey: k, onClose: { mobileForm = nil }) {
                            mobileForm = nil
                            Task { await loadApiKeys() }
                        }
                    }
                case .modelAdd:
                    ApiKeyModelFormView(onClose: { mobileForm = nil }) {
                        mobileForm = nil
                        Task { await loadModels() }
                    }
                case .modelDetail(let id):
                    if let m = store.apiKeyModels.first(where: { $0.id == id }) {
                        ApiKeyModelDetailView(model: m, onClose: { mobileForm = nil })
                    }
                case .modelEdit(let id):
                    if let m = store.apiKeyModels.first(where: { $0.id == id }) {
                        ApiKeyModelFormView(model: m, onClose: { mobileForm = nil }) {
                            mobileForm = nil
                            Task { await loadModels() }
                        }
                    }
                }
            }
        }
        .onAppear {
            Task {
                await store.loadProviders()
                await store.loadApiKeys()
                await loadProvider()
            }
        }
    }

    // MARK: 头部：随 tab 切换的搜索 + 页签
    private var headerSection: some View {
        VStack(spacing: 8) {
            if active == "provider" || active.hasPrefix("provider-") {
                if isCompact {
                    MobileSearchBar(text: $providerName,
                                    placeholder: String(format: L("common.searchFormat"), L("eum.ai.read.providerName")),
                                    filterCount: providerStatus == nil ? 0 : 1,
                                    onFilter: {
                                        providerStatus = providerStatus == nil ? 1 : nil
                                        providerPage = 1
                                        Task { await loadProvider() }
                                    },
                                    onSubmit: { providerPage = 1; Task { await loadProvider() } })
                } else {
                    QueryForm {
                        QueryField(label: L("eum.ai.read.providerName"), text: $providerName)
                        QueryPickerField(label: L("eum.status"), value: $providerStatus, options: [
                            .init(label: L("eum.status.enable"), value: 1, kind: .success),
                            .init(label: L("eum.status.disable"), value: 0, kind: .danger),
                        ])
                    } onSearch: {
                        providerPage = 1
                        Task { await loadProvider() }
                    } onReset: {
                        providerName = ""; providerStatus = nil
                        providerPage = 1
                        Task { await loadProvider() }
                    }
                }
            } else if active == "apikey" || active.hasPrefix("apikey-") {
                QueryForm {
                    QueryPickerField(label: L("eum.ai.read.providerName"), value: $apiKeyProvider, options: store.providers.map {
                        DictOption(label: $0.providerName, value: $0.id, kind: .primary)
                    })
                } onSearch: {
                    apiKeyPage = 1
                    Task { await loadApiKeys() }
                } onReset: {
                    apiKeyProvider = nil
                    apiKeyPage = 1
                    Task { await loadApiKeys() }
                }
            } else if active == "apikey-model" || active.hasPrefix("apikey-model-") {
                QueryForm {
                    QueryPickerField(label: L("eum.ai.read.apiKey"), value: $modelApiKey, options: store.apiKeys.map {
                        DictOption(label: store.apiKeyDisplay($0.id), value: $0.id, kind: .primary)
                    })
                } onSearch: {
                    modelPage = 1
                    Task { await loadModels() }
                } onReset: {
                    modelApiKey = nil
                    modelPage = 1
                    Task { await loadModels() }
                }
            }
            tabBar
        }
    }

    private var tabBar: some View {
        WireCard {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    pill("provider", "AI平台", closable: false)
                    pill("apikey", "密钥池", closable: false)
                    pill("apikey-model", "模型关联", closable: false)
                    ForEach(tabs) { tab in
                        pill(tab.name, tab.title, closable: true)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
    }

    private func pill(_ name: String, _ title: String, closable: Bool) -> some View {
        let isActive = active == name
        return Button {
            active = name
            Task {
                if name == "provider" { await loadProvider() }
                if name == "apikey" { await loadApiKeys() }
                if name == "apikey-model" { await loadModels() }
            }
        } label: {
            HStack(spacing: 5) {
                if isActive { Circle().fill(.white).frame(width: 7, height: 7) }
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(isActive ? .white : Color(hex: 0x495060))
                if closable {
                    Button {
                        closeTab(name)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(isActive ? .white : Color(hex: 0x495060))
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(isActive ? Theme.primary : Theme.panelBG)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(isActive ? Theme.primary : Color(hex: 0xD8DCE5), lineWidth: 1))
        }
    }

    private func closeTab(_ name: String) {
        tabs.removeAll { $0.name == name }
        if active == name {
            // 回退到所属列表页签
            if name.hasPrefix("apikey-model") { active = "apikey-model" }
            else if name.hasPrefix("apikey") { active = "apikey" }
            else if name.hasPrefix("provider") { active = "provider" }
            else { active = "provider" }
        }
    }

    // MARK: Provider 列表
    private var providerColumns: [TableCol] {
        [
            .init(L("eum.index"), 60, align: .center),
            .init(L("eum.ai.read.providerName"), 140),
            .init(L("eum.ai.read.providerCode"), 110),
            .init("Base URL", 220),
            .init(L("eum.status"), 70, align: .center),
            .init(L("eum.operation"), 130, align: .center),
        ]
    }

    private var providerList: some View {
        WireCard(fullHeight: true) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    WireButton(title: L("button.add"), icon: "add-circle", variant: .primary) {
                        active = open("provider-add-\(Int(Date().timeIntervalSince1970))", "新增")
                    }
                    WireButton(title: L("button.batchDelete"), icon: "delete", variant: .danger, disabled: providerSelected.isEmpty) {
                        showBatchDelete = true
                    }
                    Spacer()
                }
                .padding(12)

                WireTable(columns: providerColumns, rowCount: providerRows.count, selectable: true, selection: providerSelectedIndexes()) { idx in
                    let id = providerRows[idx].id
                    if providerSelected.contains(id) { providerSelected.remove(id) } else { providerSelected.insert(id) }
                } rowAction: { idx in
                    let p = providerRows[idx]
                    return HStack(spacing: 0) {
                        TableCell(text: "\(idx + 1)", width: 60, align: .center, color: Theme.textSecondary)
                        TableCell(text: p.providerName, width: 140)
                        TableCell(text: p.providerCode, width: 110, mono: true)
                        TableCell(text: p.baseUrl, width: 220, mono: true, color: Theme.textSecondary)
                        HStack {
                            // AI 页面直接切换无确认
                            Toggle("", isOn: Binding(
                                get: { p.status == 1 },
                                set: { on in
                                    Task {
                                        var updated = p
                                        updated.status = on ? 1 : 0
                                        do {
                                            try await store.providerUpdate(updated)
                                            providerRows = providerRows.map { $0.id == p.id ? updated : $0 }
                                            app.toastSuccess(L("common.statusUpdated"))
                                        } catch {
                                            app.toast(error, fallback: "状态更新失败")
                                        }
                                    }
                                }
                            ))
                            .labelsHidden()
                            .tint(Theme.primary)
                        }
                        .frame(width: 70, alignment: .center)
                        HStack(spacing: 10) {
                            WireButton(title: L("button.detail"), icon: "book", variant: .linkPrimary, small: true) {
                                active = open("provider-detail-\(p.id)", "详情 - \(p.providerName)")
                            }
                            WireButton(title: L("button.edit"), icon: "pencil", variant: .linkPrimary, small: true) {
                                active = open("provider-edit-\(p.id)", "编辑 - \(p.providerName)")
                            }
                        }
                        .frame(width: 130, alignment: .center)
                    }
                }

                PaginationBar(total: providerTotal, page: $providerPage, pageSize: $providerPageSize) {
                    Task { await loadProvider() }
                }
            }
        }
        .confirmationDialog(String(format: L("common.confirmDelete"), providerSelected.count), isPresented: $showBatchDelete, titleVisibility: .visible) {
            Button(L("button.delete"), role: .destructive) {
                Task {
                    do {
                        try await store.providerDelete(ids: Array(providerSelected))
                        app.toastSuccess("删除成功")
                    } catch {
                        app.toast(error, fallback: "删除失败")
                    }
                    providerSelected.removeAll()
                    await loadProvider()
                }
            }
            Button(L("button.cancel"), role: .cancel) {}
        }
    }

    // MARK: ApiKey 列表
    private var apiKeyColumns: [TableCol] {
        [
            .init(L("eum.index"), 60, align: .center),
            .init(L("eum.ai.read.providerName"), 130),
            .init(L("eum.ai.read.apiKey"), 220),
            .init(L("eum.status"), 70, align: .center),
            .init(L("eum.operation"), 130, align: .center),
        ]
    }

    private var apiKeyList: some View {
        WireCard(fullHeight: true) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    WireButton(title: L("button.add"), icon: "add-circle", variant: .primary) {
                        active = open("apikey-add-\(Int(Date().timeIntervalSince1970))", "新增")
                    }
                    WireButton(title: L("button.batchDelete"), icon: "delete", variant: .danger, disabled: apiKeySelected.isEmpty) {
                        Task {
                            do {
                                try await store.apiKeyDelete(ids: Array(apiKeySelected))
                                app.toastSuccess("删除成功")
                            } catch {
                                app.toast(error, fallback: "删除失败")
                            }
                            apiKeySelected.removeAll()
                            await loadApiKeys()
                        }
                    }
                    Spacer()
                }
                .padding(12)

                WireTable(columns: apiKeyColumns, rowCount: apiKeyRows.count, selectable: true, selection: apiKeySelectedIndexes()) { idx in
                    let id = apiKeyRows[idx].id
                    if apiKeySelected.contains(id) { apiKeySelected.remove(id) } else { apiKeySelected.insert(id) }
                } rowAction: { idx in
                    let k = apiKeyRows[idx]
                    return HStack(spacing: 0) {
                        TableCell(text: "\(idx + 1)", width: 60, align: .center, color: Theme.textSecondary)
                        TableCell(text: store.providerName(k.providerId), width: 130)
                        TableCell(text: k.apiKeyPrefix, width: 220, mono: true)
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { k.status == 1 },
                                set: { on in
                                    Task {
                                        do {
                                            try await store.apiKeyStatus(id: k.id, status: on ? 1 : 0)
                                            var updated = k
                                            updated.status = on ? 1 : 0
                                            apiKeyRows = apiKeyRows.map { $0.id == k.id ? updated : $0 }
                                            app.toastSuccess(L("common.statusUpdated"))
                                        } catch {
                                            app.toast(error, fallback: "状态更新失败")
                                        }
                                    }
                                }
                            ))
                            .labelsHidden()
                            .tint(Theme.primary)
                        }
                        .frame(width: 70, alignment: .center)
                        HStack(spacing: 10) {
                            WireButton(title: L("button.detail"), icon: "book", variant: .linkPrimary, small: true) {
                                active = open("apikey-detail-\(k.id)", "详情 - Key")
                            }
                            WireButton(title: L("button.edit"), icon: "pencil", variant: .linkPrimary, small: true) {
                                active = open("apikey-edit-\(k.id)", "编辑 - Key")
                            }
                        }
                        .frame(width: 130, alignment: .center)
                    }
                }

                PaginationBar(total: apiKeyTotal, page: $apiKeyPage, pageSize: $apiKeyPageSize) {
                    Task { await loadApiKeys() }
                }
            }
        }
    }

    // MARK: ApiKeyModel 列表
    private var modelColumns: [TableCol] {
        [
            .init(L("eum.index"), 60, align: .center),
            .init(L("ai.linkedKeys"), 220),
            .init(L("ai.modelName"), 150),
            .init(L("eum.status"), 70, align: .center),
            .init(L("eum.operation"), 130, align: .center),
        ]
    }

    private var modelList: some View {
        WireCard(fullHeight: true) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    WireButton(title: L("button.add"), icon: "add-circle", variant: .primary) {
                        active = open("apikey-model-add-\(Int(Date().timeIntervalSince1970))", "新增")
                    }
                    WireButton(title: L("button.batchDelete"), icon: "delete", variant: .danger, disabled: modelSelected.isEmpty) {
                        Task {
                            do {
                                try await store.apiKeyModelDelete(ids: Array(modelSelected))
                                app.toastSuccess("删除成功")
                            } catch {
                                app.toast(error, fallback: "删除失败")
                            }
                            modelSelected.removeAll()
                            await loadModels()
                        }
                    }
                    Spacer()
                }
                .padding(12)

                WireTable(columns: modelColumns, rowCount: modelRows.count, selectable: true, selection: modelSelectedIndexes()) { idx in
                    let id = modelRows[idx].id
                    if modelSelected.contains(id) { modelSelected.remove(id) } else { modelSelected.insert(id) }
                } rowAction: { idx in
                    let m = modelRows[idx]
                    return HStack(spacing: 0) {
                        TableCell(text: "\(idx + 1)", width: 60, align: .center, color: Theme.textSecondary)
                        TableCell(text: store.apiKeyDisplay(m.apiKeyId), width: 220, mono: true)
                        TableCell(text: m.model, width: 150)
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { m.status == 1 },
                                set: { on in
                                    Task {
                                        do {
                                            try await store.apiKeyModelStatus(id: m.id, status: on ? 1 : 0)
                                            var updated = m
                                            updated.status = on ? 1 : 0
                                            modelRows = modelRows.map { $0.id == m.id ? updated : $0 }
                                            app.toastSuccess(L("common.statusUpdated"))
                                        } catch {
                                            app.toast(error, fallback: "状态更新失败")
                                        }
                                    }
                                }
                            ))
                            .labelsHidden()
                            .tint(Theme.primary)
                        }
                        .frame(width: 70, alignment: .center)
                        HStack(spacing: 10) {
                            WireButton(title: L("button.detail"), icon: "book", variant: .linkPrimary, small: true) {
                                active = open("apikey-model-detail-\(m.id)", "详情 - \(m.model)")
                            }
                            WireButton(title: L("button.edit"), icon: "pencil", variant: .linkPrimary, small: true) {
                                active = open("apikey-model-edit-\(m.id)", "编辑 - \(m.model)")
                            }
                        }
                        .frame(width: 130, alignment: .center)
                    }
                }

                PaginationBar(total: modelTotal, page: $modelPage, pageSize: $modelPageSize) {
                    Task { await loadModels() }
                }
            }
        }
    }

    // MARK: 动态表单/详情页签
    @ViewBuilder
    private var dynTabSections: some View {
        ForEach(tabs) { tab in
            if active == tab.name {
                WireCard(fullHeight: true) {
                    dynContent(tab)
                }
            }
        }
    }

    @ViewBuilder
    private func dynContent(_ tab: DynTab) -> some View {
        if tab.name.hasPrefix("provider-") {
            if tab.name.hasPrefix("provider-add") {
                ProviderFormView(onClose: { closeTab(tab.name) }) {
                    closeTab(tab.name)
                    Task { await loadProvider() }
                }
            } else if tab.name.hasPrefix("provider-edit-") {
                let id = Int(tab.name.replacingOccurrences(of: "provider-edit-", with: "")) ?? 0
                if let p = store.providers.first(where: { $0.id == id }) {
                    ProviderFormView(provider: p, onClose: { closeTab(tab.name) }) {
                        closeTab(tab.name)
                        Task { await loadProvider() }
                    }
                }
            } else if tab.name.hasPrefix("provider-detail-") {
                let id = Int(tab.name.replacingOccurrences(of: "provider-detail-", with: "")) ?? 0
                if let p = store.providers.first(where: { $0.id == id }) {
                    ProviderDetailView(provider: p, onClose: { closeTab(tab.name) })
                }
            }
        } else if tab.name.hasPrefix("apikey-model-") {
            if tab.name.hasPrefix("apikey-model-add") {
                ApiKeyModelFormView(onClose: { closeTab(tab.name) }) {
                    closeTab(tab.name)
                    Task { await loadModels() }
                }
            } else if tab.name.hasPrefix("apikey-model-edit-") {
                let id = Int(tab.name.replacingOccurrences(of: "apikey-model-edit-", with: "")) ?? 0
                if let m = store.apiKeyModels.first(where: { $0.id == id }) {
                    ApiKeyModelFormView(model: m, onClose: { closeTab(tab.name) }) {
                        closeTab(tab.name)
                        Task { await loadModels() }
                    }
                }
            } else if tab.name.hasPrefix("apikey-model-detail-") {
                let id = Int(tab.name.replacingOccurrences(of: "apikey-model-detail-", with: "")) ?? 0
                if let m = store.apiKeyModels.first(where: { $0.id == id }) {
                    ApiKeyModelDetailView(model: m, onClose: { closeTab(tab.name) })
                }
            }
        } else if tab.name.hasPrefix("apikey-") {
            if tab.name.hasPrefix("apikey-add") {
                ApiKeyFormView(onClose: { closeTab(tab.name) }) {
                    closeTab(tab.name)
                    Task { await loadApiKeys() }
                }
            } else if tab.name.hasPrefix("apikey-edit-") {
                let id = Int(tab.name.replacingOccurrences(of: "apikey-edit-", with: "")) ?? 0
                if let k = store.apiKeys.first(where: { $0.id == id }) {
                    ApiKeyFormView(apiKey: k, onClose: { closeTab(tab.name) }) {
                        closeTab(tab.name)
                        Task { await loadApiKeys() }
                    }
                }
            } else if tab.name.hasPrefix("apikey-detail-") {
                let id = Int(tab.name.replacingOccurrences(of: "apikey-detail-", with: "")) ?? 0
                if let k = store.apiKeys.first(where: { $0.id == id }) {
                    ApiKeyDetailView(apiKey: k, onClose: { closeTab(tab.name) })
                }
            }
        }
    }

    private func open(_ name: String, _ title: String) -> String {
        if !tabs.contains(where: { $0.name == name }) {
            tabs.append(DynTab(name: name, title: title))
        }
        return name
    }

    // MARK: 手机端卡片流（provider / apikey / model）

    private var mobileProviderList: some View {
        ZStack(alignment: .bottomTrailing) {
            MobileCardList(
                cards: providerRows.map(mobileCard),
                total: providerTotal,
                selection: $providerSelected,
                batchActions: [
                    .init(title: L("button.batchDelete"), role: .danger) { showBatchDelete = true },
                ],
                onLoadMore: providerHasMore ? { await loadMoreProvider() } : nil,
                hasMore: providerHasMore
            )
            if providerSelected.isEmpty {
                MobileFAB { mobileForm = .providerAdd }
                    .padding(.trailing, 16)
                    .padding(.bottom, 18)
            }
        }
    }

    private func mobileCard(for p: AIProvider) -> MobileCardModel {
        MobileCardModel(
            id: p.id,
            title: p.providerName,
            subtitle: p.providerCode,
            initials: String(p.providerName.prefix(1)),
            showBadge: true,
            badgeText: p.status == 1 ? L("eum.status.enable") : L("eum.status.disable"),
            badgeKind: p.status == 1 ? .success : .danger,
            fields: [
                .init(label: "Base URL", value: p.baseUrl),
                .init(label: L("eum.remark"), value: p.remark.isEmpty ? "-" : p.remark),
            ],
            actions: [
                .init(title: L("button.detail")) { mobileForm = .providerDetail(p.id) },
                .init(title: L("button.edit")) { mobileForm = .providerEdit(p.id) },
                .init(title: p.status == 1 ? L("eum.status.disable") : L("eum.status.enable")) {
                    Task {
                        var updated = p
                        updated.status = p.status == 1 ? 0 : 1
                        do {
                            try await store.providerUpdate(updated)
                            providerRows = providerRows.map { $0.id == p.id ? updated : $0 }
                            app.toastSuccess(L("common.statusUpdated"))
                        } catch {
                            app.toast(error, fallback: "状态更新失败")
                        }
                    }
                },
            ]
        )
    }

    private var mobileApiKeyList: some View {
        ZStack(alignment: .bottomTrailing) {
            MobileCardList(
                cards: apiKeyRows.map(mobileCard),
                total: apiKeyTotal,
                selection: $apiKeySelected,
                batchActions: [
                    .init(title: L("button.batchDelete"), role: .danger) {
                        Task {
                            do {
                                try await store.apiKeyDelete(ids: Array(apiKeySelected))
                                app.toastSuccess("删除成功")
                            } catch {
                                app.toast(error, fallback: "删除失败")
                            }
                            apiKeySelected.removeAll()
                            await loadApiKeys()
                        }
                    },
                ],
                onLoadMore: keyHasMore ? { await loadMoreApiKeys() } : nil,
                hasMore: keyHasMore
            )
            if apiKeySelected.isEmpty {
                MobileFAB { mobileForm = .keyAdd }
                    .padding(.trailing, 16)
                    .padding(.bottom, 18)
            }
        }
    }

    private func mobileCard(for k: AIApiKey) -> MobileCardModel {
        MobileCardModel(
            id: k.id,
            title: store.providerName(k.providerId),
            subtitle: k.apiKeyPrefix,
            initials: "K",
            showBadge: true,
            badgeText: k.status == 1 ? L("eum.status.enable") : L("eum.status.disable"),
            badgeKind: k.status == 1 ? .success : .danger,
            fields: [
                .init(label: L("ai.defaultModel"), value: k.defaultModel.isEmpty ? "-" : k.defaultModel),
                .init(label: L("ai.configuredModels"), value: "\(k.models.count) 个"),
            ],
            actions: [
                .init(title: L("button.detail")) { mobileForm = .keyDetail(k.id) },
                .init(title: L("button.edit")) { mobileForm = .keyEdit(k.id) },
                .init(title: k.status == 1 ? L("eum.status.disable") : L("eum.status.enable")) {
                    Task {
                        do {
                            try await store.apiKeyStatus(id: k.id, status: k.status == 1 ? 0 : 1)
                            app.toastSuccess(L("common.statusUpdated"))
                            await loadApiKeys()
                        } catch {
                            app.toast(error, fallback: "状态更新失败")
                        }
                    }
                },
            ]
        )
    }

    private var mobileModelList: some View {
        ZStack(alignment: .bottomTrailing) {
            MobileCardList(
                cards: modelRows.map(mobileCard),
                total: modelTotal,
                selection: $modelSelected,
                batchActions: [
                    .init(title: L("button.batchDelete"), role: .danger) {
                        Task {
                            do {
                                try await store.apiKeyModelDelete(ids: Array(modelSelected))
                                app.toastSuccess("删除成功")
                            } catch {
                                app.toast(error, fallback: "删除失败")
                            }
                            modelSelected.removeAll()
                            await loadModels()
                        }
                    },
                ],
                onLoadMore: modelHasMore ? { await loadMoreModels() } : nil,
                hasMore: modelHasMore
            )
            if modelSelected.isEmpty {
                MobileFAB { mobileForm = .modelAdd }
                    .padding(.trailing, 16)
                    .padding(.bottom, 18)
            }
        }
    }

    private func mobileCard(for m: AIApiKeyModel) -> MobileCardModel {
        MobileCardModel(
            id: m.id,
            title: m.model,
            subtitle: store.apiKeyDisplay(m.apiKeyId),
            initials: "M",
            showBadge: true,
            badgeText: m.status == 1 ? L("eum.status.enable") : L("eum.status.disable"),
            badgeKind: m.status == 1 ? .success : .danger,
            fields: [
                .init(label: L("eum.remark"), value: m.remark.isEmpty ? "-" : m.remark),
            ],
            actions: [
                .init(title: L("button.detail")) { mobileForm = .modelDetail(m.id) },
                .init(title: L("button.edit")) { mobileForm = .modelEdit(m.id) },
            ]
        )
    }

    // MARK: 数据加载
    private func loadProvider(append: Bool = false) async {
        loading = true
        defer { loading = false }
        let r = (try? await store.providerPage(page: providerPage, size: providerPageSize, providerName: providerName, status: providerStatus))
            ?? PageResult(content: [], total: 0)
        providerRows = append ? providerRows + r.content : r.content
        providerTotal = r.total
        providerHasMore = !r.content.isEmpty && providerRows.count < r.total
        if !append { providerSelected.removeAll() }
    }

    private func loadMoreProvider() async {
        guard !loading, providerHasMore else { return }
        providerPage += 1
        await loadProvider(append: true)
    }

    private func loadApiKeys(append: Bool = false) async {
        loading = true
        defer { loading = false }
        try? await store.simulateNetwork()
        var list = store.apiKeys
        if let p = apiKeyProvider { list = list.filter { $0.providerId == p } }
        let r = DataService.paginate(list, page: apiKeyPage, size: apiKeyPageSize)
        apiKeyRows = append ? apiKeyRows + r.content : r.content
        apiKeyTotal = r.total
        keyHasMore = !r.content.isEmpty && apiKeyRows.count < r.total
        if !append { apiKeySelected.removeAll() }
    }

    private func loadMoreApiKeys() async {
        guard !loading, keyHasMore else { return }
        apiKeyPage += 1
        await loadApiKeys(append: true)
    }

    private func loadModels(append: Bool = false) async {
        loading = true
        defer { loading = false }
        try? await store.simulateNetwork()
        var list = store.apiKeyModels
        if let k = modelApiKey { list = list.filter { $0.apiKeyId == k } }
        let r = DataService.paginate(list, page: modelPage, size: modelPageSize)
        modelRows = append ? modelRows + r.content : r.content
        modelTotal = r.total
        modelHasMore = !r.content.isEmpty && modelRows.count < r.total
        if !append { modelSelected.removeAll() }
    }

    private func loadMoreModels() async {
        guard !loading, modelHasMore else { return }
        modelPage += 1
        await loadModels(append: true)
    }

    private func providerSelectedIndexes() -> Set<Int> {
        Set(providerRows.enumerated().compactMap { providerSelected.contains($0.element.id) ? $0.offset : nil })
    }
    private func apiKeySelectedIndexes() -> Set<Int> {
        Set(apiKeyRows.enumerated().compactMap { apiKeySelected.contains($0.element.id) ? $0.offset : nil })
    }
    private func modelSelectedIndexes() -> Set<Int> {
        Set(modelRows.enumerated().compactMap { modelSelected.contains($0.element.id) ? $0.offset : nil })
    }
}

// MARK: - Provider 表单 / 详情

struct ProviderFormView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    var provider: AIProvider? = nil
    var onClose: () -> Void
    var onSuccess: () -> Void

    @State private var form = AIProvider(id: 0, providerName: "", providerCode: "", baseUrl: "")
    @State private var loading = false
    private var isEdit: Bool { provider != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(isEdit ? "编辑供应商" : "新增供应商").font(.system(size: 16, weight: .semibold))
                FormTextField(label: L("eum.ai.read.providerName"), required: true, placeholder: "请输入供应商名称", text: $form.providerName)
                FormTextField(label: L("eum.ai.read.providerCode"), required: true, placeholder: "请输入供应商编码", text: $form.providerCode)
                FormTextField(label: "Base URL", required: true, placeholder: "请输入 Base URL，如 https://api.example.com/v1", text: $form.baseUrl)
                FormRadioRow(label: "状态", options: [(1, "启用"), (0, "禁用")], value: $form.status)
                FormTextareaField(label: L("eum.remark"), placeholder: String(format: L("eum.placeholder.inputFormat"), L("eum.remark")), text: $form.remark)
                FormActions(loading: loading) {
                    onClose()
                } onConfirm: {
                    Task { await submit() }
                }
            }
            .padding(20)
        }
        .onAppear { if let provider { form = provider } }
    }

    private func submit() async {
        guard !form.providerName.isEmpty else { app.toastError("供应商名称不能为空"); return }
        guard !form.providerCode.isEmpty else { app.toastError("供应商编码不能为空"); return }
        guard !form.baseUrl.isEmpty else { app.toastError("Base URL 不能为空"); return }
        loading = true
        defer { loading = false }
        do {
            if isEdit {
                try await store.providerUpdate(form)
                app.toastSuccess("修改成功")
            } else {
                try await store.providerInsert(form)
                app.toastSuccess("新增成功")
            }
            onSuccess()
        } catch {
            app.toast(error, fallback: "提交失败")
        }
    }
}

struct ProviderDetailView: View {
    let provider: AIProvider
    var onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("供应商详情").font(.system(size: 16, weight: .semibold))
                DetailGrid(items: [
                    .init(label: L("eum.ai.read.providerName"), value: provider.providerName),
                    .init(label: L("eum.ai.read.providerCode"), value: provider.providerCode),
                    .init(label: "Base URL", value: provider.baseUrl),
                    .init(label: L("eum.status"), value: provider.status == 1 ? L("eum.status.enable") : L("eum.status.disable")),
                    .init(label: L("eum.createBy"), value: "admin"),
                    .init(label: L("eum.createTime"), value: provider.createTime),
                    .init(label: L("eum.remark"), value: provider.remark.isEmpty ? "-" : provider.remark, span2: true),
                ])
                HStack { Spacer(); WireButton(title: L("button.close"), variant: .defaultPlain, action: onClose) }
            }
            .padding(20)
        }
    }
}

// MARK: - ApiKey 表单 / 详情

struct ApiKeyFormView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    var apiKey: AIApiKey? = nil
    var onClose: () -> Void
    var onSuccess: () -> Void

    @State private var form = AIApiKey(id: 0, providerId: 0, apiKey: "")
    @State private var loading = false
    private var isEdit: Bool { apiKey != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(isEdit ? "编辑密钥" : "新增密钥").font(.system(size: 16, weight: .semibold))

                HStack(spacing: 8) {
                    FormFieldLabel(text: L("eum.ai.read.providerName"), required: true)
                    Picker("供应商", selection: $form.providerId) {
                        Text("请选择供应商").tag(0)
                        ForEach(store.providers) { p in
                            Text(p.providerName).tag(p.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                }
                FormTextField(label: L("eum.ai.read.apiKey"), required: true, placeholder: "请输入 API 密钥", text: $form.apiKey)
                FormRadioRow(label: "状态", options: [(1, "启用"), (0, "禁用")], value: $form.status)
                FormTextareaField(label: L("eum.remark"), placeholder: String(format: L("eum.placeholder.inputFormat"), L("eum.remark")), text: $form.remark)

                FormActions(loading: loading) {
                    onClose()
                } onConfirm: {
                    Task { await submit() }
                }
            }
            .padding(20)
        }
        .onAppear { if let apiKey { form = apiKey } }
    }

    private func submit() async {
        guard form.providerId != 0 else { app.toastError("请选择供应商"); return }
        guard !form.apiKey.isEmpty else { app.toastError("API 密钥不能为空"); return }
        loading = true
        defer { loading = false }
        do {
            if isEdit {
                try await store.apiKeyUpdate(form)
                app.toastSuccess("修改成功")
            } else {
                try await store.apiKeyInsert(form)
                app.toastSuccess("新增成功")
            }
            onSuccess()
        } catch {
            app.toast(error, fallback: "提交失败")
        }
    }
}

struct ApiKeyDetailView: View {
    @EnvironmentObject var store: DataService
    let apiKey: AIApiKey
    var onClose: () -> Void
    @State private var detail: AIApiKey?

    private var shown: AIApiKey { detail ?? apiKey }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("密钥详情").font(.system(size: 16, weight: .semibold))
                DetailGrid(items: [
                    .init(label: L("eum.ai.read.providerName"), value: store.providerName(shown.providerId)),
                    .init(label: L("eum.ai.read.apiKey"), value: shown.apiKey),
                    .init(label: L("eum.status"), value: shown.status == 1 ? L("eum.status.enable") : L("eum.status.disable")),
                    .init(label: L("ai.defaultModel"), value: shown.defaultModel.isEmpty ? "-" : shown.defaultModel),
                    .init(label: L("eum.createTime"), value: shown.createTime),
                ])

                if !shown.models.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("模型列表").font(.system(size: 13)).foregroundColor(Theme.text)
                        ForEach(shown.models, id: \.modelCode) { m in
                            HStack(spacing: 6) {
                                Text("- \(m.modelName) (\(m.modelCode))")
                                    .font(.system(size: 12.5))
                                    .foregroundColor(Theme.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.pageBG)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                    }
                }

                HStack { Spacer(); WireButton(title: L("button.close"), variant: .defaultPlain, action: onClose) }
            }
            .padding(20)
        }
        .task {
            detail = try? await store.apiKeyDetail(id: apiKey.id)
        }
    }
}

// MARK: - ApiKeyModel 表单 / 详情

struct ApiKeyModelFormView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    var model: AIApiKeyModel? = nil
    var onClose: () -> Void
    var onSuccess: () -> Void

    @State private var form = AIApiKeyModel(id: 0, apiKeyId: 0, model: "")
    @State private var loading = false
    private var isEdit: Bool { model != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(isEdit ? "编辑模型关联" : "新增模型关联").font(.system(size: 16, weight: .semibold))

                HStack(spacing: 8) {
                    FormFieldLabel(text: L("ai.linkedKeys"), required: true)
                    Picker("关联密钥", selection: $form.apiKeyId) {
                        Text("请选择密钥").tag(0)
                        ForEach(store.apiKeys) { k in
                            Text(store.apiKeyDisplay(k.id)).lineLimit(1).tag(k.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                }
                FormTextField(label: L("ai.modelName"), required: true, placeholder: "请输入模型名称 (例如: gpt-4o, glm-4-flash)", text: $form.model)
                FormRadioRow(label: "状态", options: [(1, "启用"), (0, "禁用")], value: $form.status)

                FormActions(loading: loading) {
                    onClose()
                } onConfirm: {
                    Task { await submit() }
                }
            }
            .padding(20)
        }
        .onAppear { if let model { form = model } }
    }

    private func submit() async {
        guard form.apiKeyId != 0 else { app.toastError("请选择关联密钥"); return }
        guard !form.model.isEmpty else { app.toastError("模型名称不能为空"); return }
        loading = true
        defer { loading = false }
        do {
            if isEdit {
                try await store.apiKeyModelUpdate(form)
                app.toastSuccess("修改成功")
            } else {
                try await store.apiKeyModelInsert(form)
                app.toastSuccess("新增成功")
            }
            onSuccess()
        } catch {
            app.toast(error, fallback: "提交失败")
        }
    }
}

struct ApiKeyModelDetailView: View {
    @EnvironmentObject var store: DataService
    let model: AIApiKeyModel
    var onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("模型关联详情").font(.system(size: 16, weight: .semibold))
                DetailGrid(items: [
                    .init(label: L("ai.linkedKeys"), value: store.apiKeyDisplay(model.apiKeyId)),
                    .init(label: L("ai.modelName"), value: model.model),
                    .init(label: L("eum.status"), value: model.status == 1 ? L("eum.status.enable") : L("eum.status.disable")),
                    .init(label: L("eum.createTime"), value: model.createTime),
                ])
                HStack { Spacer(); WireButton(title: L("button.close"), variant: .defaultPlain, action: onClose) }
            }
            .padding(20)
        }
    }
}
