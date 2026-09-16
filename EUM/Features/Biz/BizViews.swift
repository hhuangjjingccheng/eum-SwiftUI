import SwiftUI

// MARK: - 客户管理（biz_customer）

struct BizCustomerView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var customerName = ""
    @State private var contactPhone = ""
    @State private var status: Int?
    @State private var page = 1
    @State private var pageSize = 10
    @State private var total = 0
    @State private var rows: [BizCustomer] = []
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
            case .add: return "新增客户"
            case .detail: return "客户详情"
            case .edit: return "编辑客户"
            }
        }
    }

    private var isCompact: Bool { hSize == .compact }

    private var columns: [TableCol] = [
        .init(L("eum.index"), 60, align: .center),
        .init(L("biz.customerName"), 160),
        .init(L("biz.contactPerson"), 100),
        .init(L("biz.contactPhone"), 130),
        .init(L("biz.contactEmail"), 190),
        .init(L("biz.owner"), 110),
        .init(L("user.dept"), 130),
        .init(L("eum.status"), 70, align: .center),
        .init(L("eum.createTime"), 160),
        .init(L("eum.operation"), 190, align: .center),
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
        .task {
            await load()
            if store.users.isEmpty { await store.loadUsers() }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            if isCompact {
                MobileSearchBar(text: $customerName,
                                placeholder: String(format: L("common.searchFormat"), L("biz.customerName")),
                                filterCount: (contactPhone.isEmpty ? 0 : 1) + (status == nil ? 0 : 1),
                                onFilter: { showFilter = true },
                                onSubmit: { page = 1; Task { await load() } })
                FilterChipsBar(chips: filterChips, onClearAll: {
                    contactPhone = ""; status = nil
                    page = 1
                    Task { await load() }
                })
            } else {
                QueryForm {
                    QueryField(label: L("biz.customerName"), text: $customerName)
                    QueryField(label: L("biz.contactPhone"), text: $contactPhone)
                    QueryPickerField(label: L("eum.status"), value: $status, options: DictOption.eumStatus)
                } onSearch: {
                    page = 1
                    Task { await load() }
                } onReset: {
                    customerName = ""; contactPhone = ""; status = nil
                    page = 1
                    Task { await load() }
                }
                DynTabBar(tabs: $tabs, active: $active, fixedTitle: L("list.customers"))
            }
        }
    }

    private var filterChips: [MobileFilterChip] {
        var chips: [MobileFilterChip] = []
        if !contactPhone.isEmpty {
            chips.append(.init(id: "phone", label: "电话：\(contactPhone)", onRemove: {
                contactPhone = ""
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
                    BizCustomerFormView(onClose: { mobileForm = nil }) {
                        mobileForm = nil
                        Task { await load() }
                    }
                case .edit(let id):
                    if let c = rows.first(where: { $0.id == id }) {
                        BizCustomerFormView(customer: c, onClose: { mobileForm = nil }) {
                            mobileForm = nil
                            Task { await load() }
                        }
                    }
                case .detail(let id):
                    if let c = rows.first(where: { $0.id == id }) {
                        BizCustomerDetailView(customer: c, onClose: { mobileForm = nil })
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

    private func mobileCard(for c: BizCustomer) -> MobileCardModel {
        MobileCardModel(
            id: c.id,
            title: c.customerName,
            subtitle: c.contactPerson.isEmpty ? "未填联系人" : "联系人：\(c.contactPerson)",
            initials: String(c.customerName.prefix(1)),
            showBadge: true,
            badgeText: c.status == 1 ? L("eum.status.enable") : L("eum.status.disable"),
            badgeKind: c.status == 1 ? .success : .danger,
            fields: [
                .init(label: L("biz.contactPhone"), value: c.contactPhone),
                .init(label: L("user.dept"), value: store.deptName(c.deptId)),
                .init(label: L("biz.contactEmail"), value: c.contactEmail),
                .init(label: L("biz.owner"), value: store.userName(c.ownerId)),
            ],
            actions: [
                .init(title: L("button.detail")) { mobileForm = .detail(c.id) },
                .init(title: L("button.edit")) { mobileForm = .edit(c.id) },
                .init(title: L("button.delete"), role: .danger) {
                    selected = [c.id]
                    showBatchDelete = true
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
                        Text("联系电话")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                        TextField("请输入联系电话", text: $contactPhone)
                            .font(.system(size: 13))
                            .keyboardType(.phonePad)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(Theme.panelBG)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                    }
                    HStack(spacing: 10) {
                        WireButton(title: L("button.reset"), variant: .defaultPlain) {
                            contactPhone = ""
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
        let c = rows[idx]
        return HStack(spacing: 0) {
            TableCell(text: "\(idx + 1 + (page - 1) * pageSize)", width: 60, align: .center, color: Theme.textSecondary)
            TableCell(text: c.customerName, width: 160)
            TableCell(text: c.contactPerson.isEmpty ? "-" : c.contactPerson, width: 100)
            TableCell(text: c.contactPhone, width: 130)
            TableCell(text: c.contactEmail.isEmpty ? "-" : c.contactEmail, width: 190)
            TableCell(text: store.userName(c.ownerId), width: 110)
            TableCell(text: store.deptName(c.deptId), width: 130)
            HStack {
                StatusSwitch(isOn: c.status == 1, label: c.customerName) { newValue in
                    Task { await toggleStatus(c, newValue) }
                }
            }
            .frame(width: 70, alignment: .center)
            TableCell(text: c.createTime, width: 160, color: Theme.textSecondary)
            HStack(spacing: 10) {
                WireButton(title: L("button.detail"), icon: "book", variant: .linkPrimary, small: true) {
                    active = tabs.open(name: "detail-\(c.id)", title: String(format: L("tab.detail"), c.customerName))
                }
                WireButton(title: L("button.edit"), icon: "pencil", variant: .linkPrimary, small: true) {
                    active = tabs.open(name: "edit-\(c.id)", title: String(format: L("tab.edit"), c.customerName))
                }
                WireButton(title: L("button.delete"), icon: "delete", variant: .linkDanger, small: true) {
                    selected = [c.id]
                    showBatchDelete = true
                }
            }
            .frame(width: 190, alignment: .center)
        }
    }

    @ViewBuilder
    private var formAndDetailSections: some View {
        ForEach(tabs) { tab in
            if active == tab.name {
                WireCard(fullHeight: true) {
                    if tab.name.hasPrefix("add-") {
                        BizCustomerFormView(onClose: { closeTab(tab.name) }) {
                            closeTab(tab.name)
                            Task { await load() }
                        }
                    } else if tab.name.hasPrefix("edit-") {
                        let id = Int(tab.name.replacingOccurrences(of: "edit-", with: "")) ?? 0
                        if let c = rows.first(where: { $0.id == id }) {
                            BizCustomerFormView(customer: c, onClose: { closeTab(tab.name) }) {
                                closeTab(tab.name)
                                Task { await load() }
                            }
                        }
                    } else if tab.name.hasPrefix("detail-") {
                        let id = Int(tab.name.replacingOccurrences(of: "detail-", with: "")) ?? 0
                        if let c = rows.first(where: { $0.id == id }) {
                            BizCustomerDetailView(customer: c, onClose: { closeTab(tab.name) })
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
            let result = try await store.customerPage(page: page, size: pageSize,
                                                      customerName: customerName,
                                                      contactPhone: contactPhone, status: status)
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

    private func toggleStatus(_ c: BizCustomer, _ on: Bool) async {
        do {
            try await store.customerStatus(id: c.id, status: on ? 1 : 0)
            app.toastSuccess(L("user.statusChanged"))
            rows = rows.map { $0.id == c.id ? mutate($0, status: on ? 1 : 0) : $0 }
        } catch {
            app.toast(error, fallback: "操作失败")
        }
    }

    private func mutate(_ c: BizCustomer, status: Int) -> BizCustomer {
        var copy = c
        copy.status = status
        return copy
    }

    private func doBatchDelete() async {
        do {
            try await store.customerDelete(ids: Array(selected))
            app.toastSuccess("删除成功")
            selected.removeAll()
        } catch {
            app.toast(error, fallback: "删除失败")
        }
        await load()
    }
}

// MARK: 客户表单

struct BizCustomerFormView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    var customer: BizCustomer? = nil
    var onClose: () -> Void
    var onSuccess: () -> Void

    @State private var form = BizCustomer()
    @State private var ownerSelection: Int?
    @State private var deptSelection: DeptPick?
    @State private var showOwnerPicker = false
    @State private var showDeptPicker = false
    @State private var loading = false

    private var isEdit: Bool { customer != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(isEdit ? "编辑客户" : "新增客户")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text)

                FormTextField(label: L("biz.customerName"), required: true, placeholder: "请输入客户名称", text: $form.customerName)
                FormTextField(label: L("biz.contactPerson"), placeholder: "请输入联系人", text: $form.contactPerson)
                FormTextField(label: L("biz.contactPhone"), placeholder: "11 位手机号", text: $form.contactPhone)
                    .keyboardType(.phonePad)
                FormTextField(label: L("biz.contactEmail"), placeholder: "请输入联系邮箱", text: $form.contactEmail)
                FormTextField(label: L("biz.contactAddress"), placeholder: "请输入联系地址", text: $form.address)

                pickerField(label: L("biz.owner"), text: store.userName(ownerSelection), placeholder: "请选择负责人") {
                    showOwnerPicker = true
                }
                pickerField(label: L("user.dept"), text: deptSelection.map { _ in store.deptName(form.deptId) } ?? "",
                            placeholder: "请选择所属部门") {
                    showDeptPicker = true
                }

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
            if let customer {
                form = customer
                ownerSelection = customer.ownerId
                deptSelection = customer.deptId.map { DeptPick(id: $0, name: "") }
            }
        }
        .task {
            if store.depts.isEmpty { await store.loadDeptTree() }
            if store.users.isEmpty { await store.loadUsers() }
            if store.roles.isEmpty { await store.loadRoles() }
        }
        .sheet(isPresented: $showOwnerPicker) {
            MultiCheckPicker(title: "负责人", options: store.allUsers.map { ($0.id, $0.displayLabel) },
                             selection: Binding(
                                get: { ownerSelection.map { Set([$0]) } ?? [] },
                                set: { ownerSelection = $0.first }
                             ))
        }
        .sheet(isPresented: $showDeptPicker) {
            DeptTreePicker(selected: $deptSelection)
        }
    }

    private func pickerField(label: String, text: String, placeholder: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            FormFieldLabel(text: label)
            Button(action: action) {
                HStack {
                    Text(text.isEmpty || text == "-" ? placeholder : text)
                        .font(.system(size: 13))
                        .foregroundColor(text.isEmpty || text == "-" ? Theme.textTertiary : Theme.text)
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
        guard !form.customerName.isEmpty else { app.toastError("客户名称不能为空"); return }
        if !form.contactPhone.isEmpty {
            let pattern = "^1[3-9]\\d{9}$"
            guard form.contactPhone.range(of: pattern, options: .regularExpression) != nil else {
                app.toastError("联系电话格式不正确"); return
            }
        }
        if !form.contactEmail.isEmpty, !form.contactEmail.contains("@") {
            app.toastError("联系邮箱格式不正确"); return
        }
        form.ownerId = ownerSelection
        form.deptId = deptSelection?.id
        loading = true
        defer { loading = false }
        do {
            if isEdit {
                try await store.customerUpdate(form)
                app.toastSuccess("修改成功")
            } else {
                try await store.customerInsert(form)
                app.toastSuccess("新增成功")
            }
            onSuccess()
        } catch {
            app.toast(error, fallback: "提交失败")
        }
    }
}

// MARK: 客户详情

struct BizCustomerDetailView: View {
    @EnvironmentObject var store: DataService
    let customer: BizCustomer
    var onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("客户详情")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text)
                DetailGrid(items: [
                    .init(label: L("biz.customerCode"), value: "\(customer.id)"),
                    .init(label: L("biz.customerName"), value: customer.customerName),
                    .init(label: L("biz.contactPerson"), value: customer.contactPerson.isEmpty ? "-" : customer.contactPerson),
                    .init(label: L("biz.contactPhone"), value: customer.contactPhone.isEmpty ? "-" : customer.contactPhone),
                    .init(label: L("biz.contactEmail"), value: customer.contactEmail.isEmpty ? "-" : customer.contactEmail),
                    .init(label: L("biz.owner"), value: store.userName(customer.ownerId)),
                    .init(label: L("user.dept"), value: store.deptName(customer.deptId)),
                    .init(label: L("eum.status"), value: Theme.statusText(customer.status)),
                    .init(label: L("eum.createTime"), value: customer.createTime.isEmpty ? "-" : customer.createTime),
                    .init(label: L("eum.updateTime"), value: customer.updateTime.isEmpty ? "-" : customer.updateTime),
                    .init(label: L("biz.contactAddress"), value: customer.address.isEmpty ? "-" : customer.address, span2: true),
                    .init(label: L("eum.remark"), value: customer.remark.isEmpty ? "-" : customer.remark, span2: true),
                ])
                HStack { Spacer(); WireButton(title: L("button.close"), variant: .defaultPlain, action: onClose) }
            }
            .padding(20)
        }
    }
}

// MARK: - 订单管理（biz_order）

struct BizOrderView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var orderNo = ""
    @State private var status: Int?
    @State private var page = 1
    @State private var pageSize = 10
    @State private var total = 0
    @State private var rows: [BizOrder] = []
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
            case .add: return "新增订单"
            case .detail: return "订单详情"
            case .edit: return "编辑订单"
            }
        }
    }

    private var isCompact: Bool { hSize == .compact }

    private var columns: [TableCol] = [
        .init(L("eum.index"), 60, align: .center),
        .init(L("biz.orderNo"), 170),
        .init(L("biz.customerName"), 150),
        .init(L("biz.amount"), 110, align: .trailing),
        .init(L("eum.status"), 90, align: .center),
        .init(L("eum.createBy"), 110),
        .init(L("user.dept"), 130),
        .init(L("eum.createTime"), 160),
        .init(L("eum.operation"), 190, align: .center),
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
        .task {
            await load()
            if store.users.isEmpty { await store.loadUsers() }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            if isCompact {
                MobileSearchBar(text: $orderNo,
                                placeholder: String(format: L("common.searchFormat"), L("biz.orderNo")),
                                filterCount: status == nil ? 0 : 1,
                                onFilter: { showFilter = true },
                                onSubmit: { page = 1; Task { await load() } })
                FilterChipsBar(chips: filterChips, onClearAll: {
                    status = nil
                    page = 1
                    Task { await load() }
                })
            } else {
                QueryForm {
                    QueryField(label: L("biz.orderNo"), text: $orderNo)
                    QueryPickerField(label: L("biz.orderStatus"), value: $status, options: BizOrder.statusOptions)
                } onSearch: {
                    page = 1
                    Task { await load() }
                } onReset: {
                    orderNo = ""; status = nil
                    page = 1
                    Task { await load() }
                }
                DynTabBar(tabs: $tabs, active: $active, fixedTitle: L("list.orders"))
            }
        }
    }

    private var filterChips: [MobileFilterChip] {
        guard let status else { return [] }
        return [.init(id: "status", label: "状态：\(BizOrder.statusOptions.first { $0.value == status }?.label ?? "\(status)")", onRemove: {
            self.status = nil
            page = 1
            Task { await load() }
        })]
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
                    BizOrderFormView(onClose: { mobileForm = nil }) {
                        mobileForm = nil
                        Task { await load() }
                    }
                case .edit(let id):
                    if let o = rows.first(where: { $0.id == id }) {
                        BizOrderFormView(order: o, onClose: { mobileForm = nil }) {
                            mobileForm = nil
                            Task { await load() }
                        }
                    }
                case .detail(let id):
                    if let o = rows.first(where: { $0.id == id }) {
                        BizOrderDetailView(order: o, onClose: { mobileForm = nil })
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

    private func mobileCard(for o: BizOrder) -> MobileCardModel {
        MobileCardModel(
            id: o.id,
            title: o.orderNo,
            subtitle: o.customerName.isEmpty ? "未填客户" : o.customerName,
            showBadge: true,
            badgeText: o.statusText,
            badgeKind: o.statusKind,
            fields: [
                .init(label: L("biz.amount"), value: "¥\(o.amount)"),
                .init(label: L("eum.createBy"), value: store.userName(o.creatorId)),
                .init(label: L("user.dept"), value: store.deptName(o.deptId)),
                .init(label: L("eum.createTime"), value: String(o.createTime.prefix(19))),
            ],
            actions: [
                .init(title: L("button.detail")) { mobileForm = .detail(o.id) },
                .init(title: L("biz.markPaid")) {
                    Task {
                        do {
                            try await store.orderStatus(id: o.id, status: 1)
                            app.toastSuccess(L("biz.markedPaid"))
                            await load()
                        } catch {
                            app.toast(error, fallback: "操作失败")
                        }
                    }
                },
                .init(title: L("button.delete"), role: .danger) {
                    selected = [o.id]
                    showBatchDelete = true
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
                        Text("订单状态")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                        HStack(spacing: 8) {
                            ForEach(BizOrder.statusOptions) { opt in
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
                    HStack(spacing: 10) {
                        WireButton(title: L("button.reset"), variant: .defaultPlain) {
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
        let o = rows[idx]
        return HStack(spacing: 0) {
            TableCell(text: "\(idx + 1 + (page - 1) * pageSize)", width: 60, align: .center, color: Theme.textSecondary)
            TableCell(text: o.orderNo, width: 170, mono: true)
            TableCell(text: o.customerName.isEmpty ? "-" : o.customerName, width: 150)
            TableCell(text: "¥\(o.amount)", width: 110, align: .trailing, mono: true)
            HStack { StatusTag(text: o.statusText, kind: o.statusKind) }
                .frame(width: 90, alignment: .center)
            TableCell(text: store.userName(o.creatorId), width: 110)
            TableCell(text: store.deptName(o.deptId), width: 130)
            TableCell(text: o.createTime, width: 160, color: Theme.textSecondary)
            HStack(spacing: 10) {
                WireButton(title: L("button.detail"), icon: "book", variant: .linkPrimary, small: true) {
                    active = tabs.open(name: "detail-\(o.id)", title: String(format: L("tab.detail"), o.orderNo))
                }
                WireButton(title: L("button.edit"), icon: "pencil", variant: .linkPrimary, small: true) {
                    active = tabs.open(name: "edit-\(o.id)", title: String(format: L("tab.edit"), o.orderNo))
                }
                WireButton(title: L("button.delete"), icon: "delete", variant: .linkDanger, small: true) {
                    selected = [o.id]
                    showBatchDelete = true
                }
            }
            .frame(width: 190, alignment: .center)
        }
    }

    @ViewBuilder
    private var formAndDetailSections: some View {
        ForEach(tabs) { tab in
            if active == tab.name {
                WireCard(fullHeight: true) {
                    if tab.name.hasPrefix("add-") {
                        BizOrderFormView(onClose: { closeTab(tab.name) }) {
                            closeTab(tab.name)
                            Task { await load() }
                        }
                    } else if tab.name.hasPrefix("edit-") {
                        let id = Int(tab.name.replacingOccurrences(of: "edit-", with: "")) ?? 0
                        if let o = rows.first(where: { $0.id == id }) {
                            BizOrderFormView(order: o, onClose: { closeTab(tab.name) }) {
                                closeTab(tab.name)
                                Task { await load() }
                            }
                        }
                    } else if tab.name.hasPrefix("detail-") {
                        let id = Int(tab.name.replacingOccurrences(of: "detail-", with: "")) ?? 0
                        if let o = rows.first(where: { $0.id == id }) {
                            BizOrderDetailView(order: o, onClose: { closeTab(tab.name) })
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
            let result = try await store.orderPage(page: page, size: pageSize,
                                                   orderNo: orderNo, customerId: nil, status: status)
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
            try await store.orderDelete(ids: Array(selected))
            app.toastSuccess("删除成功")
            selected.removeAll()
        } catch {
            app.toast(error, fallback: "删除失败")
        }
        await load()
    }
}

// MARK: 订单表单

struct BizOrderFormView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    var order: BizOrder? = nil
    var onClose: () -> Void
    var onSuccess: () -> Void

    @State private var form = BizOrder()
    @State private var statusSelection: Int? = 0
    @State private var creatorSelection: Int?
    @State private var deptSelection: DeptPick?
    @State private var showCreatorPicker = false
    @State private var showDeptPicker = false
    @State private var loading = false

    private var isEdit: Bool { order != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(isEdit ? "编辑订单" : "新增订单")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text)

                FormTextField(label: L("biz.orderNo"), required: true, placeholder: "请输入订单号", text: $form.orderNo)
                FormTextField(label: L("biz.customerName"), placeholder: "请输入客户名称", text: $form.customerName)
                FormTextField(label: L("biz.amount"), placeholder: "0.00", text: $form.amount)
                    .keyboardType(.decimalPad)
                FormPickerField(label: L("biz.orderStatus"), placeholder: "请选择状态", value: $statusSelection,
                                options: [(0, "待支付"), (1, "已支付"), (2, "已取消")])

                pickerField(label: L("eum.createBy"), text: store.userName(creatorSelection), placeholder: "请选择创建人") {
                    showCreatorPicker = true
                }
                pickerField(label: L("user.dept"), text: deptSelection == nil ? "" : store.deptName(form.deptId),
                            placeholder: "请选择所属部门") {
                    showDeptPicker = true
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
        .onAppear {
            if let order {
                form = order
                statusSelection = order.status
                creatorSelection = order.creatorId
                deptSelection = order.deptId.map { DeptPick(id: $0, name: "") }
            }
        }
        .task {
            if store.depts.isEmpty { await store.loadDeptTree() }
            if store.users.isEmpty { await store.loadUsers() }
        }
        .sheet(isPresented: $showCreatorPicker) {
            MultiCheckPicker(title: "创建人", options: store.allUsers.map { ($0.id, $0.displayLabel) },
                             selection: Binding(
                                get: { creatorSelection.map { Set([$0]) } ?? [] },
                                set: { creatorSelection = $0.first }
                             ))
        }
        .sheet(isPresented: $showDeptPicker) {
            DeptTreePicker(selected: $deptSelection)
        }
    }

    private func pickerField(label: String, text: String, placeholder: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            FormFieldLabel(text: label)
            Button(action: action) {
                HStack {
                    Text(text.isEmpty || text == "-" ? placeholder : text)
                        .font(.system(size: 13))
                        .foregroundColor(text.isEmpty || text == "-" ? Theme.textTertiary : Theme.text)
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
        guard !form.orderNo.isEmpty else { app.toastError("订单号不能为空"); return }
        guard let amount = Double(form.amount.trimmingCharacters(in: .whitespaces)), amount >= 0 else {
            app.toastError("订单金额必须是不小于 0 的数字"); return
        }
        form.amount = String(format: "%.2f", amount)
        form.status = statusSelection ?? 0
        form.creatorId = creatorSelection
        form.deptId = deptSelection?.id
        loading = true
        defer { loading = false }
        do {
            if isEdit {
                try await store.orderUpdate(form)
                app.toastSuccess("修改成功")
            } else {
                try await store.orderInsert(form)
                app.toastSuccess("新增成功")
            }
            onSuccess()
        } catch {
            app.toast(error, fallback: "提交失败")
        }
    }
}

// MARK: 订单详情

struct BizOrderDetailView: View {
    @EnvironmentObject var store: DataService
    let order: BizOrder
    var onClose: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("订单详情")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.text)
                DetailGrid(items: [
                    .init(label: L("biz.orderNo"), value: "\(order.id)"),
                    .init(label: L("biz.orderNo"), value: order.orderNo),
                    .init(label: L("biz.customerName"), value: order.customerName.isEmpty ? "-" : order.customerName),
                    .init(label: L("biz.amount"), value: "¥\(order.amount)"),
                    .init(label: L("biz.orderStatus"), value: order.statusText),
                    .init(label: L("eum.createBy"), value: store.userName(order.creatorId)),
                    .init(label: L("user.dept"), value: store.deptName(order.deptId)),
                    .init(label: L("eum.createTime"), value: order.createTime.isEmpty ? "-" : order.createTime),
                    .init(label: L("eum.updateTime"), value: order.updateTime.isEmpty ? "-" : order.updateTime),
                    .init(label: L("eum.remark"), value: order.remark.isEmpty ? "-" : order.remark, span2: true),
                ])
                HStack { Spacer(); WireButton(title: L("button.close"), variant: .defaultPlain, action: onClose) }
            }
            .padding(20)
        }
    }
}
