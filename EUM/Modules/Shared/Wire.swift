import SwiftUI

// MARK: - 状态标签（对应 DictTag）

enum StatusKind {
    case success, danger, warning, info, primary, mono

    var fg: Color {
        switch self {
        case .success: return Theme.success
        case .danger: return Theme.danger
        case .warning: return Theme.warning
        case .info: return Theme.info
        case .primary: return Theme.primary
        case .mono: return Theme.textSecondary
        }
    }

    var bg: Color {
        switch self {
        case .success: return Theme.successLight
        case .danger: return Theme.dangerLight
        case .warning: return Theme.warningLight
        case .info: return Theme.infoLight
        case .primary: return Theme.borderLight
        case .mono: return Theme.borderLight
        }
    }
}

struct StatusTag: View {
    let text: String
    let kind: StatusKind
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(kind.fg)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(kind.bg)
            .clipShape(RoundedCorner(radius: 3))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadius: radius)
    }
}

// MARK: - WireButton

enum WireButtonVariant {
    case primary, danger, ghost, defaultPlain, linkPrimary, linkDanger, linkPlain
}

struct WireButton: View {
    let title: String
    var icon: String? = nil
    var variant: WireButtonVariant = .defaultPlain
    var small: Bool = false
    var disabled: Bool = false
    var loading: Bool = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if loading {
                    ProgressView().scaleEffect(0.6)
                } else if let icon {
                    WireIcon.image(icon, size: small ? 12 : 14, color: fgColor)
                }
                Text(title)
            }
            .font(.system(size: small ? 12 : 13, weight: .medium))
            .foregroundColor(fgColor)
            .padding(.horizontal, small ? 10 : 14)
            .padding(.vertical, small ? 5 : 8)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedCorner(radius: 6))
        }
        .disabled(disabled || loading)
        .opacity(disabled ? 0.45 : 1)
    }

    private var fgColor: Color {
        switch variant {
        case .primary: return .white
        case .danger: return Theme.danger
        case .ghost: return Theme.textSecondary
        case .defaultPlain: return Color(hex: 0x374151)
        case .linkPrimary: return Theme.primary
        case .linkDanger: return Theme.danger
        case .linkPlain: return Theme.textSecondary
        }
    }

    private var backgroundColor: Color {
        switch variant {
        case .primary: return Theme.primary
        case .danger, .ghost, .defaultPlain: return .white
        case .linkPrimary, .linkDanger, .linkPlain: return .clear
        }
    }

    private var borderColor: Color {
        switch variant {
        case .primary: return Theme.primary
        case .danger: return Color(hex: 0xFCA5A5)
        case .ghost: return Theme.textTertiary.opacity(0.6)
        case .defaultPlain: return Theme.border
        case .linkPrimary, .linkDanger, .linkPlain: return .clear
        }
    }
}

// MARK: - WireCard

struct WireCard<Content: View>: View {
    var title: String? = nil
    var fullHeight: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Theme.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Theme.borderLight).frame(height: 1)
                    }
            }
            content
                .frame(maxWidth: .infinity, maxHeight: fullHeight ? .infinity : nil, alignment: .topLeading)
        }
        .background(Theme.panelBG)
        .clipShape(RoundedCorner(radius: Theme.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelRadius)
                .stroke(Theme.border, lineWidth: 1)
        )
        .panelShadow()
    }
}

// MARK: - WirePageHeader

struct WirePageHeader: View {
    let title: String
    var description: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 24, weight: .heavy))
                .foregroundColor(Color(hex: 0x111827))
            if !description.isEmpty {
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }
}

// MARK: - WireStatCard

struct WireStatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: 0xF3F4F6))
                    .frame(width: 52, height: 52)
                WireIcon.image(icon, size: 24, color: Color(hex: 0x111827))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                Text(value)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(Color(hex: 0x111827))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.panelBG)
        .clipShape(RoundedCorner(radius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
        .panelShadow()
    }
}

// MARK: - 表格（横滚表格，还原 WireTable）

struct TableCol {
    let title: String
    let width: CGFloat?    // nil = 弹性
    let align: TextAlignment

    init(_ title: String, _ width: CGFloat? = nil, align: TextAlignment = .leading) {
        self.title = title
        self.width = width
        self.align = align
    }
}

/// 线框表格：深色表头 + 斑马纹行 + 多选列
/// 内容宽度固定为 max(视口宽, 最小总宽)（背景 GeometryReader 只测宽度、不参与布局）：
/// - 视口足够宽时表格铺满卡片，深色表头不断尾；
/// - 需要横向滚动时表头与行总宽一致，弹性列（width == nil）在确定宽度下均分伸展，
///   任意滚动位置表头与行列位严格对齐（旧实现按各自内容理想宽排布，滚动后会错位）。
struct WireTable<Row: View>: View {
    let columns: [TableCol]
    let rowCount: Int
    var selectable: Bool = false
    var selection: Set<Int> = []
    var onToggleRow: (Int) -> Void = { _ in }
    var rowAction: (Int) -> Row

    @State private var availableWidth: CGFloat = 0

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                if rowCount == 0 {
                    emptyView
                } else {
                    ForEach(0..<rowCount, id: \.self) { index in
                        rowView(index)
                    }
                }
            }
            .frame(width: max(totalMinWidth, availableWidth))
            .background(Theme.panelBG)
        }
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { availableWidth = geo.size.width }
                    .onChange(of: geo.size.width) { _, new in availableWidth = new }
            }
        }
    }

    private var totalMinWidth: CGFloat {
        columns.reduce(60) { $0 + ($1.width ?? 110) } + (selectable ? 44 : 0)
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            if selectable {
                checkBox(isChecked: selection.count == rowCount && rowCount > 0,
                         indeterminate: !selection.isEmpty && selection.count < rowCount)
                    .frame(width: 44)
            }
            ForEach(Array(columns.enumerated()), id: \.offset) { _, col in
                Text(col.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: col.width, alignment: alignmentFor(col.align))
                    .frame(maxWidth: col.width == nil ? .infinity : nil, alignment: alignmentFor(col.align))
                    .padding(.horizontal, 8)
            }
        }
        .frame(height: 34)
        .background(Theme.tableHeaderBG)
    }

    @ViewBuilder
    private func rowView(_ index: Int) -> some View {
        HStack(spacing: 0) {
            if selectable {
                checkBox(isChecked: selection.contains(index), indeterminate: false)
                    .frame(width: 44)
                    .contentShape(Rectangle())
                    .onTapGesture { onToggleRow(index) }
            }
            rowAction(index)
        }
        .background(rowBG(index))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.borderLight).frame(height: 1)
                .padding(.leading, selectable ? 44 : 0)
        }
    }

    private func rowBG(_ index: Int) -> Color {
        index % 2 == 1 ? Theme.pageBG : Theme.panelBG
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 30))
                .foregroundColor(Theme.textTertiary)
            Text(L("common.noData"))
                .font(.system(size: 13))
                .foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
    }

    private func alignmentFor(_ a: TextAlignment) -> Alignment {
        a == .leading ? .leading : (a == .center ? .center : .trailing)
    }

    private func checkBox(isChecked: Bool, indeterminate: Bool) -> some View {
        Group {
            if isChecked || indeterminate {
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.primary).frame(width: 16, height: 16)
                    if indeterminate {
                        Rectangle().fill(.white).frame(width: 9, height: 2)
                    } else {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 3).stroke(Theme.primaryLight5, lineWidth: 1).frame(width: 16, height: 16)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

/// 表格单元格
struct TableCell: View {
    let text: String
    var width: CGFloat? = nil
    var align: TextAlignment = .leading
    var mono: Bool = false
    var color: Color = Theme.text

    var body: some View {
        Group {
            if mono {
                Text(text).font(.system(size: 12, design: .monospaced))
            } else {
                Text(text).font(.system(size: 13))
            }
        }
        .foregroundColor(color)
        .lineLimit(1)
        .truncationMode(.middle)
        .frame(width: width, alignment: align == .leading ? .leading : (align == .center ? .center : .trailing))
        .frame(maxWidth: width == nil ? .infinity : nil,
               alignment: align == .leading ? .leading : (align == .center ? .center : .trailing))
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }
}

// MARK: - 分页栏

struct PaginationBar: View {
    let total: Int
    @Binding var page: Int
    @Binding var pageSize: Int
    var onPage: () -> Void

    private var totalPages: Int { max(1, Int(ceil(Double(total) / Double(pageSize)))) }

    var body: some View {
        HStack(spacing: 10) {
            Text(L("eum.page.total") + " \(total)")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
            Spacer()
            HStack(spacing: 6) {
                pageButton(icon: "chevron.left", disabled: page <= 1) { page -= 1; onPage() }
                Text("\(page) / \(totalPages)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.text)
                    .frame(minWidth: 52)
                pageButton(icon: "chevron.right", disabled: page >= totalPages) { page += 1; onPage() }
            }
            Picker("每页", selection: $pageSize) {
                ForEach([10, 20, 30, 50], id: \.self) { s in
                    Text("\(s) " + L("eum.page.param")).font(.system(size: 11)).tag(s)
                }
            }
            .scaleEffect(0.85)
            .frame(width: 106)
            .onChange(of: pageSize) { _ in page = 1; onPage() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Theme.borderLight).frame(height: 1) }
    }

    private func pageButton(icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(disabled ? Theme.textTertiary : Theme.text)
                .frame(width: 24, height: 24)
                .background(Theme.panelBG)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
        }
        .disabled(disabled)
    }
}

// MARK: - 查询表单

struct QueryField: View {
    let label: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 12)).foregroundColor(Theme.textSecondary)
            TextField(label, text: $text)
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.panelBG)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                .frame(width: 120)
        }
    }
}

struct QueryPickerField: View {
    let label: String
    @Binding var value: Int?
    let options: [DictOption]

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 12)).foregroundColor(Theme.textSecondary)
            Picker(label, selection: $value) {
                Text(label).tag(Int?.none)
                ForEach(options) { o in
                    Text(o.label).tag(Int?.some(o.value))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 120)
        }
    }
}

/// 搜索区卡片：字段 + 搜索/重置按钮
struct QueryForm<Fields: View>: View {
    @ViewBuilder var fields: Fields
    var onSearch: () -> Void
    var onReset: () -> Void

    var body: some View {
        WireCard {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) { fields }
                }
                HStack(spacing: 8) {
                    WireButton(title: L("button.search"), icon: "search-circle", variant: .primary, small: true, action: onSearch)
                    WireButton(title: L("button.reset"), icon: "refresh", variant: .defaultPlain, small: true, action: onReset)
                }
            }
            .padding(12)
        }
    }
}

// MARK: - 动态页签（el-tabs 胶囊样式）

struct DynTab: Identifiable, Equatable {
    let name: String
    let title: String
    var id: String { name }
}

struct DynTabBar: View {
    @Binding var tabs: [DynTab]
    @Binding var active: String
    /// 固定首页签（不可关闭）
    var fixedTitle: String
    var fixedValue: String = "list"

    var body: some View {
        WireCard {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    pill(DynTab(name: fixedValue, title: fixedTitle), closable: false)
                    ForEach(tabs) { tab in
                        pill(tab, closable: true)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
    }

    private func pill(_ tab: DynTab, closable: Bool) -> some View {
        let isActive = active == tab.name
        return Button {
            active = tab.name
        } label: {
            HStack(spacing: 5) {
                if isActive {
                    Circle().fill(.white).frame(width: 7, height: 7)
                }
                Text(tab.title)
                    .font(.system(size: 12))
                    .foregroundColor(isActive ? .white : Color(hex: 0x495060))
                if closable {
                    Button {
                        close(tab)
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

    private func close(_ tab: DynTab) {
        tabs.removeAll { $0.name == tab.name }
        if active == tab.name { active = fixedValue }
    }
}

extension Array where Element == DynTab {
    /// 打开（或切换到）一个动态页签
    mutating func open(name: String, title: String) -> String {
        if !contains(where: { $0.name == name }) {
            append(DynTab(name: name, title: title))
        }
        return name
    }
}

// MARK: - 表单控件

struct FormFieldLabel: View {
    let text: String
    var required: Bool = false
    var body: some View {
        HStack(spacing: 2) {
            if required {
                Text("*").foregroundColor(Theme.danger)
            }
            Text(text).font(.system(size: 13)).foregroundColor(Theme.text)
        }
        .frame(width: 96, alignment: .leading)
    }
}

struct FormTextField: View {
    let label: String
    var required: Bool = false
    var placeholder: String = ""
    @Binding var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            FormFieldLabel(text: label, required: required)
            TextField(placeholder, text: $text)
                .font(.system(size: 13))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Theme.panelBG)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
        }
    }
}

struct FormNumberField: View {
    let label: String
    var required: Bool = false
    var min: Int = 0
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 8) {
            FormFieldLabel(text: label, required: required)
            HStack(spacing: 0) {
                stepButton("minus") { if value > min { value -= 1 } }
                TextField("0", value: $value, format: .number.grouping(.never))
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .frame(width: 56)
                    .keyboardType(.numbersAndPunctuation)
                stepButton("plus") { value += 1 }
            }
            .background(Theme.panelBG)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
        }
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Theme.text)
                .frame(width: 26, height: 28)
        }
        .buttonStyle(.plain)
    }
}

struct FormPickerField<T: Hashable>: View {
    let label: String
    var required: Bool = false
    var placeholder: String = ""
    @Binding var value: T?
    let options: [(T, String)]

    var body: some View {
        HStack(spacing: 8) {
            FormFieldLabel(text: label, required: required)
            Picker(placeholder, selection: $value) {
                Text(placeholder.isEmpty ? "请选择" : placeholder).tag(T?.none)
                ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                    Text(opt.1).tag(T?.some(opt.0))
                }
            }
            .pickerStyle(.menu)
        }
    }
}

struct FormRadioRow: View {
    let label: String
    let options: [(Int, String)]
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 8) {
            FormFieldLabel(text: label)
            HStack(spacing: 14) {
                ForEach(options, id: \.0) { opt in
                    Button {
                        value = opt.0
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: value == opt.0 ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 13))
                                .foregroundColor(value == opt.0 ? Theme.primary : Theme.textTertiary)
                            Text(opt.1).font(.system(size: 13)).foregroundColor(Theme.text)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct FormTextareaField: View {
    let label: String
    var placeholder: String = ""
    @Binding var text: String
    var lineLimit: Int = 3

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            FormFieldLabel(text: label)
                .padding(.top, 6)
            TextField(placeholder, text: $text, axis: .vertical)
                .font(.system(size: 13))
                .lineLimit(lineLimit...6)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Theme.panelBG)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
        }
    }
}

/// 表单底部按钮
struct FormActions: View {
    var confirmTitle: String = "确定"
    var loading: Bool = false
    var onCancel: () -> Void
    var onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Spacer()
            WireButton(title: L("button.cancel"), variant: .defaultPlain, action: onCancel)
            WireButton(title: confirmTitle, variant: .primary, loading: loading, action: onConfirm)
        }
        .padding(.top, 20)
    }
}

// MARK: - 详情网格（el-descriptions column=2）

struct DetailItem: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    var span2: Bool = false
}

struct DetailGrid: View {
    let items: [DetailItem]
    var columnSpacing: CGFloat = 10
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        if hSize == .compact {
            // 手机端单列：长值（邮箱 / 时间等）独占整行，避免窄列内折成多行
            VStack(spacing: columnSpacing) {
                ForEach(items) { detailRow($0) }
            }
        } else {
            let span2Items = items.filter { $0.span2 }
            let pairItems = rowsChunked(items.filter { !$0.span2 })
            VStack(spacing: columnSpacing) {
                ForEach(span2Items) { item in
                    detailRow(item)
                }
                ForEach(pairItems.indices, id: \.self) { rowIdx in
                    HStack(alignment: .top, spacing: columnSpacing) {
                        ForEach(pairItems[rowIdx]) { detailCell($0) }
                    }
                }
            }
        }
    }

    private func rowsChunked(_ items: [DetailItem]) -> [[DetailItem]] {
        stride(from: 0, to: items.count, by: 2).map { Array(items[$0..<min($0 + 2, items.count)]) }
    }

    private func detailRow(_ item: DetailItem) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(item.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 92, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
                .background(Theme.pageBG)
            Text(item.value)
                .font(.system(size: 13))
                .foregroundColor(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 8)
        }
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.border, lineWidth: 1))
    }

    private func detailCell(_ item: DetailItem) -> some View {
        detailRow(item)
    }
}

// MARK: - Toast 覆盖层

struct ToastOverlay: View {
    let toast: ToastMessage?

    var body: some View {
        VStack {
            if let toast {
                HStack(spacing: 8) {
                    Image(systemName: iconName(toast.kind))
                        .foregroundColor(iconColor(toast.kind))
                    Text(toast.text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.text)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.white)
                .clipShape(RoundedCorner(radius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
                .panelShadow()
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .padding(.top, 8)
        .animation(.spring(duration: 0.3), value: toast)
        .allowsHitTesting(false)
    }

    private func iconName(_ kind: ToastMessage.Kind) -> String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    private func iconColor(_ kind: ToastMessage.Kind) -> Color {
        switch kind {
        case .success: return Theme.success
        case .error: return Theme.danger
        case .info: return Theme.linkBlue
        case .warning: return Theme.warning
        }
    }
}

// MARK: - 状态开关（带确认）

struct StatusSwitch: View {
    let isOn: Bool
    var label: String = ""
    var onChange: (Bool) -> Void

    @State private var pendingValue: Bool?

    var body: some View {
        Button {
            pendingValue = !isOn
        } label: {
            Toggle("", isOn: .constant(isOn))
                .labelsHidden()
                .tint(Theme.primary)
                .allowsHitTesting(false)
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            String(format: L("common.confirmStatus"), isOn ? L("eum.status.disable") : L("eum.status.enable"), label.isEmpty ? "" : " \"\(label)\""),
            isPresented: Binding(get: { pendingValue != nil }, set: { if !$0 { pendingValue = nil } }),
            titleVisibility: .visible
        ) {
            Button(isOn ? "停用" : "启用", role: .destructive) {
                if let v = pendingValue { onChange(v) }
                pendingValue = nil
            }
            Button(L("button.cancel"), role: .cancel) { pendingValue = nil }
        }
    }
}

// MARK: - 加载中

struct TableLoadingOverlay: View {
    var loading: Bool
    var body: some View {
        if loading {
            ZStack {
                Theme.pageBG.opacity(0.7).ignoresSafeArea()
                VStack(spacing: 8) {
                    ProgressView()
                    Text(L("common.loading"))
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(18)
                .background(.white)
                .clipShape(RoundedCorner(radius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
            }
        }
    }
}

// MARK: - 页面容器（PageLayout：固定头部 + 滚动主体）

struct PageLayout<Header: View, Body: View>: View {
    let header: Header
    private let content: Body
    /// false：内容自管滚动（移动端卡片流 / 表单自带 ScrollView），避免同轴嵌套
    /// 导致列表被撑开、FAB 与多选操作栏无法悬浮固定
    private let scrolls: Bool

    init(header: Header, scrolls: Bool = true, @ViewBuilder content: () -> Body) {
        self.header = header
        self.scrolls = scrolls
        self.content = content()
    }

    var body: some View {
        Group {
            if scrolls {
                VStack(spacing: Theme.gap) {
                    header
                    ScrollView(showsIndicators: true) {
                        content
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(.bottom, 16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 0) {
                    header
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .padding(Theme.gap)
    }
}
