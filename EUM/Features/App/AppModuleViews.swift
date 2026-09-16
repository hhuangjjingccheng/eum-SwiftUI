import SwiftUI

// MARK: - 授权管理（卡片网格）

struct LicenseView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    @Environment(\.horizontalSizeClass) private var hSize

    private var isCompact: Bool { hSize == .compact }

    @State private var machineId = ""
    @State private var licenseKey = ""
    @State private var page = 1
    @State private var pageSize = 10
    @State private var total = 0
    @State private var rows: [License] = []
    @State private var loading = false

    @State private var showIssue = false
    @State private var showDevices: License?
    @State private var revokeTarget: License?

    var body: some View {
        PageLayout(header: QueryForm {
            QueryField(label: L("license.machineId"), text: $machineId)
            QueryField(label: L("license.licenseKey"), text: $licenseKey)
        } onSearch: {
            page = 1
            Task { await load() }
        } onReset: {
            machineId = ""; licenseKey = ""
            page = 1
            Task { await load() }
        }, scrolls: !isCompact) {
            WireCard(fullHeight: true) {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        WireButton(title: L("license.issue"), icon: "add-circle", variant: .primary) { showIssue = true }
                        Spacer()
                    }
                    .padding(12)

                    ScrollView {
                        // 宽屏两列网格（对齐 web 2 列 grid），窄屏单列
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 430), spacing: 16)], spacing: 16) {
                            if rows.isEmpty {
                                VStack(spacing: 10) {
                                    Image(systemName: "tray").font(.system(size: 30)).foregroundColor(Theme.textTertiary)
                                    Text("暂无授权数据").font(.system(size: 13)).foregroundColor(Theme.textTertiary)
                                }
                                .frame(maxWidth: .infinity)
                                .gridCellColumns(2)
                                .padding(.vertical, 60)
                            }
                            ForEach(rows) { license in
                                LicenseCard(license: license) {
                                    showDevices = license
                                } onRevoke: {
                                    revokeTarget = license
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                    }

                    PaginationBar(total: total, page: $page, pageSize: $pageSize) {
                        Task { await load() }
                    }
                }
            }
        }
        .overlay { TableLoadingOverlay(loading: loading) }
        .task { await load() }
        .sheet(isPresented: $showIssue) {
            IssueLicenseForm { app.toastSuccess(L("license.issued")) }
                .environmentObject(app).environmentObject(store)
        }
        .sheet(item: $showDevices) { license in
            LicenseDevicesSheet(license: license)
                .environmentObject(store)
        }
        .confirmationDialog(L("license.confirmRevoke"),
                            isPresented: Binding(get: { revokeTarget != nil }, set: { if !$0 { revokeTarget = nil } }),
                            titleVisibility: .visible) {
            Button(L("license.revokeBtn"), role: .destructive) {
                if let t = revokeTarget {
                    Task {
                        do {
                            try await store.licenseRevoke(id: t.id)
                            app.toastSuccess(L("license.revoked"))
                            await load()
                        } catch {
                            app.toast(error, fallback: "吊销失败")
                        }
                    }
                }
                revokeTarget = nil
            }
            Button(L("button.cancel"), role: .cancel) { revokeTarget = nil }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let r = (try? await store.licensePage(page: page, size: pageSize, machineId: machineId, licenseKey: licenseKey))
            ?? PageResult(content: [], total: 0)
        rows = r.content
        total = r.total
    }
}

// MARK: - 授权单卡片

struct LicenseCard: View {
    @EnvironmentObject var store: DataService
    let license: License
    var onViewDevices: () -> Void
    var onRevoke: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Rectangle().fill(Theme.linkBlue).frame(width: 4, height: 16)
                Text("授权单 #\(license.id)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                Button(action: onViewDevices) {
                    HStack(spacing: 4) {
                        WireIcon.image("monitor", size: 13, color: Theme.textSecondary)
                        Text("查看设备").font(.system(size: 12)).foregroundColor(Theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                StatusTag(
                    text: license.status == 1 ? "正常" : "已吊销",
                    kind: license.status == 1 ? .success : .danger
                )
                if license.status == 1 {
                    WireButton(title: L("license.revoke"), icon: "delete", variant: .danger, small: true, action: onRevoke)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(hex: 0xF8F9FA))

            // 指标行
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("授权类型").font(.system(size: 11)).foregroundColor(Theme.textTertiary)
                    StatusTag(text: license.typeText, kind: license.isTrial ? .warning : .success)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("最大设备数").font(.system(size: 11)).foregroundColor(Theme.textTertiary)
                    Text(license.maxDevices.map { "\($0)" } ?? "不限制")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.text)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 3) {
                    Text("过期时间").font(.system(size: 11)).foregroundColor(Theme.textTertiary)
                    Text(license.expireText)
                        .font(.system(size: 13, weight: license.expiresAt.isEmpty ? .bold : .medium))
                        .foregroundColor(license.expiresAt.isEmpty ? Theme.success : Theme.text)
                }
            }
            .padding(14)

            // 密钥块
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("授权密钥").font(.system(size: 11)).foregroundColor(Theme.textTertiary)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = license.licenseKey
                        AppState.shared.toastSuccess(L("license.keyCopied"))
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.on.doc").font(.system(size: 11))
                            Text("复制密钥").font(.system(size: 11))
                        }
                        .foregroundColor(Theme.linkBlue)
                    }
                    .buttonStyle(.plain)
                }
                Text(license.licenseKey)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.monoText)
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
                    .padding(10)
                    .background(Theme.monoDark)
                    .clipShape(RoundedCorner(radius: 4))
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)

            // meta
            VStack(alignment: .leading, spacing: 3) {
                Text("颁发时间：\(license.issuedAt)")
                if !license.remark.isEmpty {
                    Text("备注：\(license.remark)").lineLimit(1)
                }
            }
            .font(.system(size: 11))
            .foregroundColor(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color(hex: 0xE5E7EB).opacity(0.8))
                    .frame(height: 1)
            }
        }
        .background(Theme.panelBG)
        .clipShape(RoundedCorner(radius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        .panelShadow()
    }
}

// MARK: - 颁发授权表单

struct IssueLicenseForm: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    var onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var userId = ""
    @State private var licenseType = "trial"
    @State private var maxDevices = 1
    @State private var validDays = 30
    @State private var remark = ""
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        FormFieldLabel(text: L("uralyt.userId"))
                        TextField("用户ID", text: $userId)
                            .keyboardType(.numberPad)
                            .font(.system(size: 13))
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(Theme.panelBG)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                    }

                    HStack(spacing: 8) {
                        FormFieldLabel(text: L("license.grantType"), required: true)
                        Picker("授权类型", selection: $licenseType) {
                            Text("试用版 (trial)").tag("trial")
                            Text("正式版 (pro)").tag("pro")
                            Text("企业版 (enterprise)").tag("enterprise")
                        }
                        .pickerStyle(.menu)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                    }

                    FormNumberField(label: "最大设备数", min: 1, value: $maxDevices)

                    FormNumberField(label: "有效天数", min: 0, value: $validDays)
                    Text("(0代表永久)")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                        .padding(.leading, 104)

                    FormTextareaField(label: L("eum.remark"), placeholder: "备注信息", text: $remark, lineLimit: 2)

                    FormActions(confirmTitle: "确认颁发", loading: loading) {
                        dismiss()
                    } onConfirm: {
                        Task { await submit() }
                    }
                }
                .padding(20)
            }
            .navigationTitle("颁发授权")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: licenseType) { newType in
            // 非 trial 时天数置 0 并禁用；恢复 trial 时回 30
            if newType != "trial" {
                validDays = 0
            } else if validDays == 0 {
                validDays = 30
            }
        }
    }

    private func submit() async {
        loading = true
        defer { loading = false }
        do {
            try await store.licenseIssue(
                userId: Int(userId), licenseType: licenseType,
                maxDevices: maxDevices, validDays: validDays, remark: remark
            )
            onSuccess()
            dismiss()
        } catch {
            app.toast(error, fallback: "颁发失败")
        }
    }
}

// MARK: - 已绑定设备列表弹窗

struct LicenseDevicesSheet: View {
    @EnvironmentObject var store: DataService
    let license: License
    @Environment(\.dismiss) private var dismiss
    @State private var devices: [Device] = []

    private func load() async {
        devices = await store.devices(of: license)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        TableCell(text: "机器码", width: 200, color: .white)
                        TableCell(text: "设备名称", width: 130, color: .white)
                        TableCell(text: "邮箱", width: 150, color: .white)
                        TableCell(text: "状态", width: 70, align: .center, color: .white)
                        TableCell(text: "最后活跃时间", width: 160, color: .white)
                    }
                    .background(Theme.tableHeaderBG)

                    if devices.isEmpty {
                        Text("暂无绑定设备")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textTertiary)
                            .padding(20)
                    }
                    ForEach(devices) { d in
                        HStack(spacing: 0) {
                            TableCell(text: d.machineId, width: 200, mono: true)
                            TableCell(text: d.deviceName, width: 130)
                            TableCell(text: d.email, width: 150)
                            TableCell(text: d.status == 1 ? "在线" : "离线", width: 70, align: .center,
                                      color: d.status == 1 ? Theme.success : Theme.info)
                            TableCell(text: d.lastActiveTime, width: 160, color: Theme.textSecondary)
                        }
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderLight).frame(height: 1) }
                    }
                }
            }
            .navigationTitle("已绑定设备列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }.font(.system(size: 13))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await load() }
    }
}

// MARK: - 设备管理

struct DeviceView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var machineId = ""
    @State private var deviceName = ""
    @State private var email = ""
    @State private var page = 1
    @State private var pageSize = 10
    @State private var total = 0
    @State private var rows: [Device] = []
    @State private var loading = false
    @State private var hasMore = false
    @State private var showFilter = false

    @State private var bindTarget: Device?
    @State private var bindKeyText = ""
    @State private var confirmUnbind: Device?
    @State private var confirmRebind: Device?

    private var isCompact: Bool { hSize == .compact }

    private var columns: [TableCol] = [
        .init("ID", 46, align: .center),
        .init(L("device.machineId"), 190),
        .init(L("device.deviceName"), 130),
        .init(L("eum.user.read.email"), 150),
        .init(L("license.id"), 70, align: .center),
        .init(L("license.licenseKey"), 170),
        .init(L("device.lastActive"), 150),
        .init(L("eum.status"), 70, align: .center),
        .init(L("eum.operation"), 110, align: .center),
    ]

    var body: some View {
        PageLayout(header: headerSection, scrolls: !isCompact) {
            if isCompact {
                mobileList
            } else {
                desktopList
            }
        }
        .overlay { TableLoadingOverlay(loading: loading) }
        .task { await load() }
        .sheet(isPresented: $showFilter) { filterSheet }
        .sheet(item: $bindTarget) { device in
            bindKeySheet(device)
        }
        .confirmationDialog(
            "确认解除机器码为 \"\(confirmUnbind?.machineId ?? "")\" 的设备绑定吗？该操作不可逆，设备将失去当前授权。",
            isPresented: Binding(get: { confirmUnbind != nil }, set: { if !$0 { confirmUnbind = nil } }),
            titleVisibility: .visible
        ) {
            Button("解除绑定", role: .destructive) {
                if let d = confirmUnbind {
                    Task {
                        do {
                            try await store.deviceUnbind(id: d.id)
                            app.toastSuccess(L("device.unbindDone"))
                            await load()
                        } catch {
                            app.toast(error, fallback: "解绑失败")
                        }
                    }
                }
                confirmUnbind = nil
            }
            Button(L("button.cancel"), role: .cancel) { confirmUnbind = nil }
        }
        .confirmationDialog(
            "确认重新绑定机器码为 \"\(confirmRebind?.machineId ?? "")\" 的设备吗？",
            isPresented: Binding(get: { confirmRebind != nil }, set: { if !$0 { confirmRebind = nil } }),
            titleVisibility: .visible
        ) {
            Button("确定绑定") {
                if let d = confirmRebind {
                    Task {
                        do {
                            try await store.deviceRebind(id: d.id)
                            app.toastSuccess(L("device.rebindDone"))
                            await load()
                        } catch {
                            app.toast(error, fallback: "绑定失败")
                        }
                    }
                }
                confirmRebind = nil
            }
            Button(L("button.cancel"), role: .cancel) { confirmRebind = nil }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            if isCompact {
                MobileSearchBar(text: $machineId,
                                placeholder: String(format: L("common.searchFormat"), L("license.machineId")),
                                filterCount: (deviceName.isEmpty ? 0 : 1) + (email.isEmpty ? 0 : 1),
                                onFilter: { showFilter = true },
                                onSubmit: { page = 1; Task { await load() } })
                FilterChipsBar(chips: filterChips, onClearAll: {
                    deviceName = ""; email = ""
                    page = 1
                    Task { await load() }
                })
            } else {
                QueryForm {
                    QueryField(label: L("license.machineId"), text: $machineId)
                    QueryField(label: L("device.deviceName"), text: $deviceName)
                    QueryField(label: L("eum.user.read.email"), text: $email)
                } onSearch: {
                    page = 1
                    Task { await load() }
                } onReset: {
                    machineId = ""; deviceName = ""; email = ""
                    page = 1
                    Task { await load() }
                }
            }
        }
    }

    private var filterChips: [MobileFilterChip] {
        var chips: [MobileFilterChip] = []
        if !deviceName.isEmpty {
            chips.append(.init(id: "name", label: "名称：\(deviceName)", onRemove: {
                deviceName = ""
                page = 1
                Task { await load() }
            }))
        }
        if !email.isEmpty {
            chips.append(.init(id: "email", label: "邮箱：\(email)", onRemove: {
                email = ""
                page = 1
                Task { await load() }
            }))
        }
        return chips
    }

    /// 手机端筛选弹层
    private var filterSheet: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("设备名称")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                        TextField("请输入设备名称", text: $deviceName)
                            .font(.system(size: 13))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .background(Theme.panelBG)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("邮箱")
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
                            deviceName = ""
                            email = ""
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

    private var mobileList: some View {
        MobileCardList(
            cards: rows.map(mobileCard),
            total: total,
            selection: .constant([]),
            onLoadMore: hasMore ? { await loadMore() } : nil,
            hasMore: hasMore
        )
    }

    private func mobileCard(for d: Device) -> MobileCardModel {
        var actions: [MobileCardModel.Action] = []
        if d.licenseId == nil {
            actions.append(.init(title: L("license.bindKey")) {
                bindKeyText = ""
                bindTarget = d
            })
        } else if d.status == 1 {
            actions.append(.init(title: L("license.unbind"), role: .danger) { confirmUnbind = d })
        } else {
            actions.append(.init(title: L("license.rebind")) { confirmRebind = d })
        }
        return MobileCardModel(
            id: d.id,
            title: d.deviceName.isEmpty ? "设备 #\(d.id)" : d.deviceName,
            subtitle: d.machineId,
            initials: "D",
            showBadge: true,
            badgeText: d.status == 1 ? "正常" : "已解绑",
            badgeKind: d.status == 1 ? .success : .info,
            fields: [
                .init(label: L("eum.user.read.email"), value: d.email),
                .init(label: L("license.title"), value: d.licenseId.map { "#\($0)" } ?? "-"),
                .init(label: L("license.licenseKey"), value: d.licenseKey.isEmpty ? "-" : String(d.licenseKey.prefix(18)) + "…"),
                .init(label: L("device.lastActive"), value: String(d.lastActiveTime.prefix(19))),
            ],
            actions: actions,
            selectable: false
        )
    }

    private var desktopList: some View {
        WireCard(fullHeight: true) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text("设备通过 SDK 自动注册并绑定，无需手动新增")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textTertiary)
                    Spacer()
                    WireButton(title: L("auth.deviceApply"), icon: "create", variant: .ghost, small: true) {
                        app.showDeviceApply = true
                    }
                }
                .padding(12)

                WireTable(columns: columns, rowCount: rows.count) { idx in
                    row(idx)
                }

                PaginationBar(total: total, page: $page, pageSize: $pageSize) {
                    Task { await load() }
                }
            }
        }
    }

    private func row(_ idx: Int) -> some View {
        let d = rows[idx]
        return HStack(spacing: 0) {
            TableCell(text: "\(d.id)", width: 46, align: .center, color: Theme.textSecondary)
            TableCell(text: d.machineId, width: 190, mono: true)
            TableCell(text: d.deviceName, width: 130)
            TableCell(text: d.email, width: 150)
            TableCell(text: d.licenseId.map { "\($0)" } ?? "-", width: 70, align: .center, color: Theme.textSecondary)
            TableCell(
                text: d.licenseKey.isEmpty ? "-" : (String(d.licenseKey.prefix(20)) + "..."),
                width: 170, mono: true, color: Theme.textSecondary
            )
            TableCell(text: d.lastActiveTime, width: 150, color: Theme.textSecondary)
            StatusTag(text: d.status == 1 ? "正常" : "已解绑", kind: d.status == 1 ? .success : .info)
                .frame(width: 70, alignment: .center)
            HStack {
                if d.licenseId == nil {
                    WireButton(title: L("license.bindKey"), icon: "key", variant: .linkPrimary, small: true) {
                        bindKeyText = ""
                        bindTarget = d
                    }
                } else if d.status == 1 {
                    WireButton(title: L("license.unbind"), icon: "delete", variant: .linkDanger, small: true) {
                        confirmUnbind = d
                    }
                } else {
                    WireButton(title: L("license.rebind"), icon: "link", variant: .linkPrimary, small: true) {
                        confirmRebind = d
                    }
                }
            }
            .frame(width: 110, alignment: .center)
        }
    }

    private func bindKeySheet(_ device: Device) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("机器码：\(device.machineId)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(Theme.textSecondary)
                FormTextareaField(label: L("license.licenseKey"), placeholder: "请输入有效的授权密钥进行绑定", text: $bindKeyText)
                FormActions(confirmTitle: "确定") {
                    bindTarget = nil
                } onConfirm: {
                    guard !bindKeyText.isEmpty else {
                        app.toastError("授权密钥不能为空")
                        return
                    }
                    Task {
                        do {
                            try await store.deviceBindKey(id: device.id, licenseKey: bindKeyText)
                            app.toastSuccess(L("device.bindDone"))
                            bindTarget = nil
                            await load()
                        } catch {
                            app.toast(error, fallback: "绑定失败")
                        }
                    }
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("绑定密钥")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { bindTarget = nil }.font(.system(size: 13))
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func load(append: Bool = false) async {
        loading = true
        defer { loading = false }
        let r = (try? await store.devicePage(page: page, size: pageSize, machineId: machineId, deviceName: deviceName, email: email))
            ?? PageResult(content: [], total: 0)
        rows = append ? rows + r.content : r.content
        total = r.total
        hasMore = !r.content.isEmpty && rows.count < r.total
    }

    private func loadMore() async {
        guard !loading, hasMore else { return }
        page += 1
        await load(append: true)
    }
}

// MARK: - 设备授权申请（独立免登录页）

struct DeviceApplyView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    var isSheet: Bool = false
    @Environment(\.dismiss) private var dismiss

    @State private var machineId = ""
    @State private var email = ""
    @State private var submitting = false
    @State private var submitted = false

    var body: some View {
        ZStack {
            Color(hex: 0xF0F2F5).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("请务必填写真实的机器特征码和能接受邮件的联系邮箱，激活密钥会通过邮件发送给您。")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.danger)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("设备授权申请")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Theme.text)
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 14) {
                        CarbonTextField(title: L("device.machineId"), placeholder: "请输入您的机器特征码", text: $machineId)
                        CarbonTextField(title: L("biz.contactEmail"), placeholder: "请输入联系邮箱", text: $email, keyboard: .emailAddress)
                    }

                    CarbonPrimaryButton(title: "提交申请", loadingTitle: "提交中...", loading: submitting) {
                        Task { await submit() }
                    }

                    if submitted {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("申请成功", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.success)
                            Text("您的设备申请已提交成功，请耐心等待管理员处理。")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(12)
                        .background(Theme.successLight)
                        .clipShape(RoundedCorner(radius: 4))
                    }
                }
                .padding(28)
                .background(.white)
                .clipShape(RoundedCorner(radius: 8))
                .panelShadow()
                .padding(20)
            }
        }
        .overlay(alignment: .topLeading) {
            if isSheet {
                EmptyView()
            } else {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                        .padding(10)
                        .background(.white)
                        .clipShape(Circle())
                }
                .padding(.leading, 16)
                .padding(.top, 8)
            }
        }
    }

    private func submit() async {
        guard !machineId.isEmpty else { app.toastError("机器特征码不能为空"); return }
        guard !email.isEmpty else { app.toastError("邮箱不能为空"); return }
        guard email.contains("@"), email.contains(".") else { app.toastError("请输入正确的邮箱格式"); return }
        submitting = true
        defer { submitting = false }
        do {
            try await store.deviceApply(machineId: machineId, email: email)
            submitted = true
            app.toastSuccess(L("device.applySubmitted"))
        } catch {
            app.toast(error, fallback: "申请失败")
        }
    }
}

// MARK: - 插件市场

struct PluginView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var showAdd = false
    @State private var editing: Plugin?

    private var isCompact: Bool { hSize == .compact }

    private var columns: [TableCol] = [
        .init(L("eum.index"), 55, align: .center),
        .init(L("plugin.id"), 190),
        .init(L("plugin.name"), 120),
        .init(L("plugin.version"), 70),
        .init(L("plugin.vendor"), 110),
        .init(L("plugin.description")),
        .init(L("eum.status"), 70, align: .center),
        .init(L("plugin.needRestart"), 60, align: .center),
        .init(L("eum.operation"), 70, align: .center),
    ]

    var body: some View {
        PageLayout(header: QueryForm {
            Text("插件市场管理：您可以在此查看、添加、修改插件信息")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
        } onSearch: {
            Task { await store.loadPlugins() }
        } onReset: {
            Task { await store.loadPlugins() }
        }, scrolls: !isCompact) {
            if isCompact {
                MobileCardList(
                    cards: store.plugins.map(mobileCard),
                    total: store.plugins.count,
                    selection: .constant([]),
                    onLoadMore: nil,
                    hasMore: false
                )
            } else {
                WireCard(fullHeight: true) {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            WireButton(title: L("plugin.add"), icon: "add-circle", variant: .primary) { showAdd = true }
                            Spacer()
                        }
                        .padding(12)

                        WireTable(columns: columns, rowCount: store.plugins.count) { idx in
                            row(idx)
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if isCompact {
                MobileFAB { showAdd = true }
                    .padding(.trailing, 16)
                    .padding(.bottom, 18)
            }
        }
        .sheet(isPresented: $showAdd) {
            PluginForm(existing: nil) { app.toastSuccess("新增成功") }
                .environmentObject(app).environmentObject(store)
        }
        .sheet(item: $editing) { plugin in
            PluginForm(existing: plugin) { app.toastSuccess("修改成功") }
                .environmentObject(app).environmentObject(store)
        }
        .task { await store.loadPlugins() }
    }

    private func mobileCard(for p: Plugin) -> MobileCardModel {
        MobileCardModel(
            id: p.id,
            title: p.name,
            subtitle: "\(p.pluginId) · v\(p.version)",
            initials: String(p.name.prefix(1)),
            showBadge: true,
            badgeText: p.status == 1 ? "已上架" : "待处理",
            badgeKind: p.status == 1 ? .success : .info,
            fields: [
                .init(label: L("plugin.vendor"), value: p.vendor.isEmpty ? "-" : p.vendor),
                .init(label: L("plugin.description"), value: p.descriptionText.isEmpty ? "-" : p.descriptionText),
                .init(label: L("plugin.needRestart"), value: p.requiresRestart ? "是" : "否"),
            ],
            actions: [
                .init(title: L("button.edit")) { editing = p },
            ],
            selectable: false
        )
    }

    private func row(_ idx: Int) -> some View {
        let p = store.plugins[idx]
        return HStack(spacing: 0) {
            TableCell(text: "\(idx + 1)", width: 55, align: .center, color: Theme.textSecondary)
            TableCell(text: p.pluginId, width: 190, mono: true)
            TableCell(text: p.name, width: 120)
            TableCell(text: p.version, width: 70)
            TableCell(text: p.vendor, width: 110)
            TableCell(text: p.descriptionText)
            StatusTag(text: p.status == 1 ? "已上架" : "待处理", kind: p.status == 1 ? .success : .info)
                .frame(width: 70, alignment: .center)
            StatusTag(text: p.requiresRestart ? "是" : "否", kind: p.requiresRestart ? .warning : .success)
                .frame(width: 60, alignment: .center)
            WireButton(title: L("button.edit"), icon: "pencil", variant: .linkPrimary, small: true) {
                editing = p
            }
            .frame(width: 70, alignment: .center)
        }
    }
}

struct PluginForm: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    var existing: Plugin?
    var onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var form = Plugin(id: 0, pluginId: "", name: "", version: "1.0.0", vendor: "", descriptionText: "")
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FormTextField(label: L("plugin.id"), required: true, placeholder: "例如: com.example.plugin", text: $form.pluginId)
                    FormTextField(label: L("plugin.name"), required: true, placeholder: "请输入插件名称", text: $form.name)
                    FormTextField(label: L("plugin.version"), placeholder: "例如: 1.0.0", text: $form.version)
                    FormTextField(label: L("plugin.vendor"), placeholder: "请输入开发商", text: $form.vendor)
                    FormTextField(label: L("plugin.iconUrl"), placeholder: "请输入图标的完整URL", text: $form.iconUrl)
                    FormTextField(label: L("plugin.downloadUrl"), placeholder: "请输入插件包的下载URL", text: $form.downloadUrl)

                    HStack(spacing: 8) {
                        FormFieldLabel(text: L("plugin.needRestart"))
                        Toggle("", isOn: $form.requiresRestart).labelsHidden().tint(Theme.primary)
                    }
                    HStack(spacing: 8) {
                        FormFieldLabel(text: L("langgraph.sessionBinding"))
                        Toggle("", isOn: $form.sessionBound).labelsHidden().tint(Theme.primary)
                    }
                    FormRadioRow(label: "状态", options: [(0, "待处理"), (1, "已上架")], value: $form.status)
                    FormTextareaField(label: L("plugin.description"), placeholder: "请输入插件功能描述", text: $form.descriptionText, lineLimit: 4)

                    FormActions {
                        dismiss()
                    } onConfirm: {
                        Task { await submit() }
                    }
                }
                .padding(20)
            }
            .navigationTitle(existing == nil ? "新增插件" : "编辑插件")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { if let existing { form = existing } }
    }

    private func submit() async {
        guard !form.pluginId.isEmpty else { app.toastError("插件ID不能为空"); return }
        guard !form.name.isEmpty else { app.toastError("插件名称不能为空"); return }
        loading = true
        defer { loading = false }
        do {
            try await store.pluginSave(form)
            onSuccess()
            dismiss()
        } catch {
            app.toast(error, fallback: "保存失败")
        }
    }
}
