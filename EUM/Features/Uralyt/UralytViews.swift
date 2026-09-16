import SwiftUI

// MARK: - 患者用户（uralyt-u/user）

struct UralytUserView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var page = 1
    @State private var pageSize = 10
    @State private var total = 0
    @State private var rows: [UralytUser] = []
    @State private var loading = false
    @State private var hasMore = false
    @State private var selected: Set<Int> = []
    @State private var showBatchDelete = false
    @State private var showAdd = false
    @State private var editing: UralytUser?
    @State private var deleteTarget: UralytUser?

    private var isCompact: Bool { hSize == .compact }

    private var columns: [TableCol] = [
        .init(L("eum.index"), 60, align: .center),
        .init(L("uralyt.username"), 130),
        .init(L("eum.user.read.phone"), 130),
        .init(L("eum.user.read.nickName"), 110),
        .init(L("eum.user.read.gender"), 70, align: .center),
        .init(L("uralyt.status"), 80, align: .center),
        .init(L("eum.createTime"), 150),
        .init(L("eum.operation"), 120, align: .center),
    ]

    var body: some View {
        PageLayout(header: QueryForm {
            EmptyView()
        } onSearch: {
            page = 1
            Task { await load(append: false) }
        } onReset: {
            page = 1
            Task { await load(append: false) }
        }, scrolls: !isCompact) {
            if isCompact {
                mobileList
            } else {
                WireCard(fullHeight: true) {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            WireButton(title: L("button.add"), icon: "add-circle", variant: .primary) { showAdd = true }
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
                            Task { await load(append: false) }
                        }
                    }
                }
            }
        }
        .overlay { TableLoadingOverlay(loading: loading) }
        .task { await load() }
        .sheet(isPresented: $showAdd) {
            UralytUserForm(existing: nil) { app.toastSuccess("新增成功") }
                .environmentObject(app).environmentObject(store)
        }
        .sheet(item: $editing) { user in
            UralytUserForm(existing: user) { app.toastSuccess("修改成功") }
                .environmentObject(app).environmentObject(store)
        }
        .confirmationDialog(String(format: L("common.confirmDelete"), selected.count), isPresented: $showBatchDelete, titleVisibility: .visible) {
            Button(L("button.delete"), role: .destructive) { Task { await doBatchDelete() } }
            Button(L("button.cancel"), role: .cancel) {}
        }
        .confirmationDialog(String(format: L("user.confirmDelete"), deleteTarget?.username ?? ""), isPresented: Binding(
            get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }
        ), titleVisibility: .visible) {
            Button(L("button.delete"), role: .destructive) {
                if let t = deleteTarget {
                    Task {
                        do {
                            try await store.uralytUserDelete(ids: [t.id])
                            app.toastSuccess("删除成功")
                            await load()
                        } catch {
                            app.toast(error, fallback: "删除失败")
                        }
                    }
                }
                deleteTarget = nil
            }
            Button(L("button.cancel"), role: .cancel) { deleteTarget = nil }
        }
    }

    private func row(_ idx: Int) -> some View {
        let user = rows[idx]
        return HStack(spacing: 0) {
            TableCell(text: "\(idx + 1 + (page - 1) * pageSize)", width: 60, align: .center, color: Theme.textSecondary)
            TableCell(text: user.username, width: 130)
            TableCell(text: user.phone, width: 130)
            TableCell(text: user.nickname, width: 110)
            TableCell(text: user.genderText, width: 70, align: .center)
            TableCell(text: user.statusText, width: 80, align: .center)
            TableCell(text: user.createTime, width: 150, color: Theme.textSecondary)
            HStack(spacing: 8) {
                WireButton(title: L("button.edit"), icon: "pencil", variant: .linkPrimary, small: true) { editing = user }
                WireButton(title: L("button.delete"), icon: "delete", variant: .linkDanger, small: true) { deleteTarget = user }
            }
            .frame(width: 120, alignment: .center)
        }
    }

    private func selectedIndexes() -> Set<Int> {
        Set(rows.enumerated().compactMap { selected.contains($0.element.id) ? $0.offset : nil })
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
                MobileFAB { showAdd = true }
                    .padding(.trailing, 16)
                    .padding(.bottom, 18)
            }
        }
    }

    private func mobileCard(for user: UralytUser) -> MobileCardModel {
        MobileCardModel(
            id: user.id,
            title: user.nickname.isEmpty ? user.username : user.nickname,
            subtitle: user.username,
            initials: String((user.nickname.isEmpty ? user.username : user.nickname).prefix(1)),
            showBadge: true,
            badgeText: user.statusText,
            badgeKind: user.statusText == "正常" ? .success : .danger,
            fields: [
                .init(label: L("eum.user.read.phone"), value: user.phone),
                .init(label: L("eum.user.read.gender"), value: user.genderText),
                .init(label: L("eum.createTime"), value: String(user.createTime.prefix(19))),
            ],
            actions: [
                .init(title: L("button.edit")) { editing = user },
                .init(title: L("button.delete"), role: .danger) { deleteTarget = user },
            ]
        )
    }

    private func load(append: Bool = false) async {
        loading = true
        defer { loading = false }
        let r = (try? await store.uralytUserPage(page: page, size: pageSize)) ?? PageResult(content: [], total: 0)
        rows = append ? rows + r.content : r.content
        total = r.total
        hasMore = !r.content.isEmpty && rows.count < r.total
        if !append { selected.removeAll() }
    }

    private func loadMore() async {
        guard !loading, hasMore else { return }
        page += 1
        await load(append: true)
    }

    private func doBatchDelete() async {
        do {
            try await store.uralytUserDelete(ids: Array(selected))
            app.toastSuccess("删除成功")
        } catch {
            app.toast(error, fallback: "删除失败")
        }
        selected.removeAll()
        await load()
    }
}

struct UralytUserForm: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    var existing: UralytUser?
    var onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var form = UralytUser(id: 0, username: "", phone: "", nickname: "")
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FormTextField(label: L("uralyt.username"), placeholder: "用户账号", text: $form.username)
                    FormTextField(label: L("eum.user.read.phone"), placeholder: "手机号码", text: $form.phone)
                    FormTextField(label: L("auth.login.password"), placeholder: "密码", text: $form.password)
                    FormTextField(label: L("eum.user.read.nickName"), placeholder: "用户昵称", text: $form.nickname)
                    HStack(spacing: 8) {
                        FormFieldLabel(text: L("eum.user.read.gender"))
                        Picker("用户性别", selection: $form.gender) {
                            Text("男").tag("1")
                            Text("女").tag("0")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                    HStack(spacing: 8) {
                        FormFieldLabel(text: L("uralyt.status"))
                        Picker("帐号状态", selection: $form.status) {
                            Text("正常").tag("1")
                            Text("停用").tag("0")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                    FormTextField(label: L("uralyt.avatar"), placeholder: "头像地址", text: $form.avatar)
                    FormActions {
                        dismiss()
                    } onConfirm: {
                        Task { await submit() }
                    }
                }
                .padding(20)
            }
            .navigationTitle(existing == nil ? "新增患者用户" : "编辑患者用户")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { if let existing { form = existing } }
    }

    private func submit() async {
        loading = true
        defer { loading = false }
        do {
            if existing != nil {
                try await store.uralytUserUpdate(form)
                app.toastSuccess("修改成功")
            } else {
                try await store.uralytUserInsert(form)
                app.toastSuccess("新增成功")
            }
            onSuccess()
            dismiss()
        } catch {
            app.toast(error, fallback: "提交失败")
        }
    }
}

// MARK: - 尿酸记录（uralyt-u/uric）

struct UricRecordView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var page = 1
    @State private var pageSize = 10
    @State private var total = 0
    @State private var rows: [UricRecord] = []
    @State private var loading = false
    @State private var hasMore = false
    @State private var selected: Set<Int> = []
    @State private var showBatchDelete = false
    @State private var showAdd = false
    @State private var editing: UricRecord?
    @State private var deleteTarget: UricRecord?

    private var isCompact: Bool { hSize == .compact }

    private var columns: [TableCol] = [
        .init(L("eum.index"), 60, align: .center),
        .init(L("user.userId"), 70, align: .center),
        .init(L("uralyt.recordDate"), 100, align: .center),
        .init(L("uralyt.morningPh"), 70, align: .center),
        .init(L("uralyt.noonPh"), 70, align: .center),
        .init(L("uralyt.eveningPh"), 70, align: .center),
        .init(L("eum.createTime"), 150),
        .init(L("eum.operation"), 120, align: .center),
    ]

    var body: some View {
        PageLayout(header: QueryForm {
            EmptyView()
        } onSearch: {
            page = 1
            Task { await load(append: false) }
        } onReset: {
            page = 1
            Task { await load(append: false) }
        }, scrolls: !isCompact) {
            if isCompact {
                mobileList
            } else {
                WireCard(fullHeight: true) {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            WireButton(title: L("button.add"), icon: "add-circle", variant: .primary) { showAdd = true }
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
                            Task { await load(append: false) }
                        }
                    }
                }
            }
        }
        .overlay { TableLoadingOverlay(loading: loading) }
        .task { await load() }
        .sheet(isPresented: $showAdd) {
            UricRecordForm(existing: nil) { app.toastSuccess("新增成功") }
                .environmentObject(app).environmentObject(store)
        }
        .sheet(item: $editing) { rec in
            UricRecordForm(existing: rec) { app.toastSuccess("修改成功") }
                .environmentObject(app).environmentObject(store)
        }
        .confirmationDialog(String(format: L("common.confirmDelete"), selected.count), isPresented: $showBatchDelete, titleVisibility: .visible) {
            Button(L("button.delete"), role: .destructive) { Task { await doBatchDelete() } }
            Button(L("button.cancel"), role: .cancel) {}
        }
        .confirmationDialog(L("uralyt.confirmDeleteRecord"), isPresented: Binding(
            get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }
        ), titleVisibility: .visible) {
            Button(L("button.delete"), role: .destructive) {
                if let t = deleteTarget {
                    Task {
                        do {
                            try await store.uricDelete(ids: [t.id])
                            app.toastSuccess("删除成功")
                            await load()
                        } catch {
                            app.toast(error, fallback: "删除失败")
                        }
                    }
                }
                deleteTarget = nil
            }
            Button(L("button.cancel"), role: .cancel) { deleteTarget = nil }
        }
    }

    private func row(_ idx: Int) -> some View {
        let rec = rows[idx]
        return HStack(spacing: 0) {
            TableCell(text: "\(idx + 1 + (page - 1) * pageSize)", width: 60, align: .center, color: Theme.textSecondary)
            TableCell(text: "\(rec.userId)", width: 70, align: .center)
            TableCell(text: rec.recordDate, width: 100, align: .center)
            TableCell(text: rec.morningPh, width: 70, align: .center)
            TableCell(text: rec.noonPh, width: 70, align: .center)
            TableCell(text: rec.eveningPh, width: 70, align: .center)
            TableCell(text: rec.createTime, width: 150, color: Theme.textSecondary)
            HStack(spacing: 8) {
                WireButton(title: L("button.edit"), icon: "pencil", variant: .linkPrimary, small: true) { editing = rec }
                WireButton(title: L("button.delete"), icon: "delete", variant: .linkDanger, small: true) { deleteTarget = rec }
            }
            .frame(width: 120, alignment: .center)
        }
    }

    private func selectedIndexes() -> Set<Int> {
        Set(rows.enumerated().compactMap { selected.contains($0.element.id) ? $0.offset : nil })
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
                MobileFAB { showAdd = true }
                    .padding(.trailing, 16)
                    .padding(.bottom, 18)
            }
        }
    }

    private func mobileCard(for rec: UricRecord) -> MobileCardModel {
        MobileCardModel(
            id: rec.id,
            title: "记录 \(rec.recordDate.isEmpty ? "-" : rec.recordDate)",
            subtitle: "用户 ID \(rec.userId)",
            initials: "pH",
            fields: [
                .init(label: L("uralyt.morningPh"), value: rec.morningPh.isEmpty ? "-" : rec.morningPh),
                .init(label: L("uralyt.noonPh"), value: rec.noonPh.isEmpty ? "-" : rec.noonPh),
                .init(label: L("uralyt.eveningPh"), value: rec.eveningPh.isEmpty ? "-" : rec.eveningPh),
                .init(label: L("eum.remark"), value: rec.notes.isEmpty ? "-" : rec.notes),
            ],
            actions: [
                .init(title: L("button.edit")) { editing = rec },
                .init(title: L("button.delete"), role: .danger) { deleteTarget = rec },
            ]
        )
    }

    private func load(append: Bool = false) async {
        loading = true
        defer { loading = false }
        let r = (try? await store.uricPage(page: page, size: pageSize)) ?? PageResult(content: [], total: 0)
        rows = append ? rows + r.content : r.content
        total = r.total
        hasMore = !r.content.isEmpty && rows.count < r.total
        if !append { selected.removeAll() }
    }

    private func loadMore() async {
        guard !loading, hasMore else { return }
        page += 1
        await load(append: true)
    }

    private func doBatchDelete() async {
        do {
            try await store.uricDelete(ids: Array(selected))
            app.toastSuccess("删除成功")
        } catch {
            app.toast(error, fallback: "删除失败")
        }
        selected.removeAll()
        await load()
    }
}

struct UricRecordForm: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    var existing: UricRecord?
    var onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var form = UricRecord(id: 0, userId: 1, recordDate: "", morningPh: "", noonPh: "", eveningPh: "")
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FormNumberField(label: "用户ID", required: true, min: 1, value: $form.userId)
                    FormTextField(label: L("uralyt.recordDate"), required: true, placeholder: "YYYY-MM-DD", text: $form.recordDate)
                    FormTextField(label: L("uralyt.morningPh"), placeholder: "如 6.2", text: $form.morningPh)
                    FormTextField(label: L("uralyt.noonPh"), placeholder: "如 6.5", text: $form.noonPh)
                    FormTextField(label: L("uralyt.eveningPh"), placeholder: "如 6.8", text: $form.eveningPh)
                    FormTextField(label: L("uralyt.morningDose"), placeholder: "如 0.5g", text: $form.morningDosage)
                    FormTextField(label: L("uralyt.noonDose"), placeholder: "如 0.5g", text: $form.noonDosage)
                    FormTextField(label: L("uralyt.eveningDose"), placeholder: "如 1.0g", text: $form.eveningDosage)
                    FormTextareaField(label: L("eum.remark"), placeholder: "备注", text: $form.notes)
                    FormActions {
                        dismiss()
                    } onConfirm: {
                        Task { await submit() }
                    }
                }
                .padding(20)
            }
            .navigationTitle(existing == nil ? "新增尿酸记录" : "编辑尿酸记录")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            if let existing {
                form = existing
            } else {
                form.recordDate = "2026-06-20"
            }
        }
    }

    private func submit() async {
        loading = true
        defer { loading = false }
        do {
            if existing != nil {
                try await store.uricUpdate(form)
                app.toastSuccess("修改成功")
            } else {
                try await store.uricInsert(form)
                app.toastSuccess("新增成功")
            }
            onSuccess()
            dismiss()
        } catch {
            app.toast(error, fallback: "提交失败")
        }
    }
}

// MARK: - 用药记录（uralyt-u/medical）

struct MedicalRecordView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    @Environment(\.horizontalSizeClass) private var hSize

    @State private var page = 1
    @State private var pageSize = 10
    @State private var total = 0
    @State private var rows: [MedicalRecord] = []
    @State private var loading = false
    @State private var hasMore = false
    @State private var selected: Set<Int> = []
    @State private var showBatchDelete = false
    @State private var showAdd = false
    @State private var editing: MedicalRecord?
    @State private var deleteTarget: MedicalRecord?

    private var isCompact: Bool { hSize == .compact }

    private var columns: [TableCol] = [
        .init(L("eum.index"), 60, align: .center),
        .init(L("user.userId"), 70, align: .center),
        .init(L("uralyt.testDate"), 100, align: .center),
        .init(L("uralyt.testType"), 110),
        .init(L("uralyt.indicator")),
        .init(L("uralyt.doctorNote")),
        .init(L("eum.createTime"), 150),
        .init(L("eum.operation"), 120, align: .center),
    ]

    var body: some View {
        PageLayout(header: QueryForm {
            EmptyView()
        } onSearch: {
            page = 1
            Task { await load(append: false) }
        } onReset: {
            page = 1
            Task { await load(append: false) }
        }, scrolls: !isCompact) {
            if isCompact {
                mobileList
            } else {
                WireCard(fullHeight: true) {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            WireButton(title: L("button.add"), icon: "add-circle", variant: .primary) { showAdd = true }
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
                            Task { await load(append: false) }
                        }
                    }
                }
            }
        }
        .overlay { TableLoadingOverlay(loading: loading) }
        .task { await load() }
        .sheet(isPresented: $showAdd) {
            MedicalRecordForm(existing: nil) { app.toastSuccess("新增成功") }
                .environmentObject(app).environmentObject(store)
        }
        .sheet(item: $editing) { rec in
            MedicalRecordForm(existing: rec) { app.toastSuccess("修改成功") }
                .environmentObject(app).environmentObject(store)
        }
        .confirmationDialog(String(format: L("common.confirmDelete"), selected.count), isPresented: $showBatchDelete, titleVisibility: .visible) {
            Button(L("button.delete"), role: .destructive) { Task { await doBatchDelete() } }
            Button(L("button.cancel"), role: .cancel) {}
        }
        .confirmationDialog(L("uralyt.confirmDeleteRecord"), isPresented: Binding(
            get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }
        ), titleVisibility: .visible) {
            Button(L("button.delete"), role: .destructive) {
                if let t = deleteTarget {
                    Task {
                        do {
                            try await store.medicalDelete(ids: [t.id])
                            app.toastSuccess("删除成功")
                            await load()
                        } catch {
                            app.toast(error, fallback: "删除失败")
                        }
                    }
                }
                deleteTarget = nil
            }
            Button(L("button.cancel"), role: .cancel) { deleteTarget = nil }
        }
    }

    private func row(_ idx: Int) -> some View {
        let rec = rows[idx]
        return HStack(spacing: 0) {
            TableCell(text: "\(idx + 1 + (page - 1) * pageSize)", width: 60, align: .center, color: Theme.textSecondary)
            TableCell(text: "\(rec.userId)", width: 70, align: .center)
            TableCell(text: rec.recordDate, width: 100, align: .center)
            TableCell(text: rec.recordType, width: 110)
            TableCell(text: rec.indicators)
            TableCell(text: rec.doctorNotes.isEmpty ? "-" : rec.doctorNotes)
            TableCell(text: rec.createTime, width: 150, color: Theme.textSecondary)
            HStack(spacing: 8) {
                WireButton(title: L("button.edit"), icon: "pencil", variant: .linkPrimary, small: true) { editing = rec }
                WireButton(title: L("button.delete"), icon: "delete", variant: .linkDanger, small: true) { deleteTarget = rec }
            }
            .frame(width: 120, alignment: .center)
        }
    }

    private func selectedIndexes() -> Set<Int> {
        Set(rows.enumerated().compactMap { selected.contains($0.element.id) ? $0.offset : nil })
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
                MobileFAB { showAdd = true }
                    .padding(.trailing, 16)
                    .padding(.bottom, 18)
            }
        }
    }

    private func mobileCard(for rec: MedicalRecord) -> MobileCardModel {
        MobileCardModel(
            id: rec.id,
            title: "化验 \(rec.recordDate.isEmpty ? "-" : rec.recordDate)",
            subtitle: "用户 ID \(rec.userId) · \(rec.recordType.isEmpty ? "未分类" : rec.recordType)",
            initials: "检",
            fields: [
                .init(label: L("uralyt.indicator"), value: rec.indicators.isEmpty ? "-" : rec.indicators),
                .init(label: L("uralyt.doctorNote"), value: rec.doctorNotes.isEmpty ? "-" : rec.doctorNotes),
            ],
            actions: [
                .init(title: L("button.edit")) { editing = rec },
                .init(title: L("button.delete"), role: .danger) { deleteTarget = rec },
            ]
        )
    }

    private func load(append: Bool = false) async {
        loading = true
        defer { loading = false }
        let r = (try? await store.medicalPage(page: page, size: pageSize)) ?? PageResult(content: [], total: 0)
        rows = append ? rows + r.content : r.content
        total = r.total
        hasMore = !r.content.isEmpty && rows.count < r.total
        if !append { selected.removeAll() }
    }

    private func loadMore() async {
        guard !loading, hasMore else { return }
        page += 1
        await load(append: true)
    }

    private func doBatchDelete() async {
        do {
            try await store.medicalDelete(ids: Array(selected))
            app.toastSuccess("删除成功")
        } catch {
            app.toast(error, fallback: "删除失败")
        }
        selected.removeAll()
        await load()
    }
}

struct MedicalRecordForm: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    var existing: MedicalRecord?
    var onSuccess: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var form = MedicalRecord(id: 0, userId: 1, recordDate: "", recordType: "", indicators: "")
    @State private var loading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FormNumberField(label: "用户ID", required: true, min: 1, value: $form.userId)
                    FormTextField(label: L("uralyt.testDate"), required: true, placeholder: "YYYY-MM-DD", text: $form.recordDate)
                    FormTextField(label: L("uralyt.testType"), placeholder: "如 尿常规 / 血尿酸", text: $form.recordType)
                    FormTextareaField(label: L("uralyt.indicator"), placeholder: "化验指标", text: $form.indicators)
                    FormTextareaField(label: L("uralyt.doctorNote"), placeholder: "医生备注", text: $form.doctorNotes, lineLimit: 2)
                    FormActions {
                        dismiss()
                    } onConfirm: {
                        Task { await submit() }
                    }
                }
                .padding(20)
            }
            .navigationTitle(existing == nil ? "新增用药记录" : "编辑用药记录")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            if let existing {
                form = existing
            } else {
                form.recordDate = "2026-06-20"
            }
        }
    }

    private func submit() async {
        loading = true
        defer { loading = false }
        do {
            if existing != nil {
                try await store.medicalUpdate(form)
                app.toastSuccess("修改成功")
            } else {
                try await store.medicalInsert(form)
                app.toastSuccess("新增成功")
            }
            onSuccess()
            dismiss()
        } catch {
            app.toast(error, fallback: "提交失败")
        }
    }
}
