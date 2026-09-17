import SwiftUI

// MARK: - MobileKit（第三套 UI 风格：compact 卡片流）
// 桌面（regular）继续使用 WireTable / QueryForm / DynTabBar；
// 手机（compact）由本组件库承接：导航栏 + 搜索筛选 + 卡片流 + 多选操作栏 + 加载更多。

// MARK: - 卡片模型（各列表页把一行数据映射成一张卡片）

struct MobileCardModel: Identifiable {
    struct Field: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    struct Action: Identifiable {
        enum Role { case normal, danger }
        let title: String
        var role: Role = .normal
        let handler: () -> Void
        var id: String { title }
    }

    let id: Int
    let title: String
    var subtitle: String = ""
    /// 头像占位字（默认取标题首字）
    var initials: String = ""
    var showBadge: Bool = false
    var badgeText: String = ""
    var badgeKind: StatusKind = .success
    /// 中部字段，最多展示 4 个（2 列 × 2 行）
    var fields: [Field] = []
    var actions: [Action] = []
    /// 是否参与多选（详情类卡片可关闭）
    var selectable: Bool = true
}

// MARK: - 顶部搜索 + 筛选入口

struct MobileSearchBar: View {
    @Binding var text: String
    var placeholder: String = "搜索"
    var filterCount: Int = 0
    var onFilter: () -> Void
    var onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textTertiary)
                TextField(placeholder, text: $text)
                    .font(.system(size: 13))
                    .submitLabel(.search)
                    .onSubmit(onSubmit)
                if !text.isEmpty {
                    Button {
                        text = ""
                        onSubmit()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Theme.panelBG)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))

            Button(action: onFilter) {
                ZStack(alignment: .topTrailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 13))
                        Text(L("button.filter"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Theme.text)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Theme.panelBG)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                    if filterCount > 0 {
                        Text("\(filterCount)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 14, minHeight: 14)
                            .background(Theme.danger)
                            .clipShape(Circle())
                            .offset(x: 5, y: -5)
                    }
                }
            }
        }
    }
}

// MARK: - 已选条件 chips

struct MobileFilterChip: Identifiable {
    let id: String
    let label: String
    let onRemove: () -> Void
}

struct FilterChipsBar: View {
    let chips: [MobileFilterChip]
    var onClearAll: (() -> Void)? = nil

    var body: some View {
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(chips) { chip in
                        Button(action: chip.onRemove) {
                            HStack(spacing: 4) {
                                Text(chip.label)
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.text)
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(Theme.textTertiary)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color(hex: 0xF3F4F6))
                            .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
                            .clipShape(Capsule())
                        }
                    }
                    if let onClearAll {
                        Button("清除", action: onClearAll)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.linkBlue)
                    }
                }
            }
        }
    }
}

// MARK: - 卡片列表（含多选 + 加载更多）

struct MobileCardList: View {
    let cards: [MobileCardModel]
    var total: Int
    @Binding var selection: Set<Int>
    /// 多选模式底部的批量操作
    var batchActions: [MobileCardModel.Action] = []
    /// 页脚出现时触发加载下一页（nil 表示无更多）
    var onLoadMore: (() async -> Void)?
    var hasMore: Bool = false

    @State private var selectMode = false
    @State private var loadingMore = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            // LazyVStack：长列表只构建可见卡片，滚动更稳
            LazyVStack(spacing: 10) {
                if selectMode {
                    selectHeader
                }
                if cards.isEmpty {
                    emptyState
                }
                ForEach(cards) { card in
                    cardView(card)
                }
                footer
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 90)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if selectMode && !selection.isEmpty {
                batchBar
            }
        }
        .onChange(of: selection) { _, newValue in
            if newValue.isEmpty && selectMode { selectMode = false }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 30))
                .foregroundColor(Theme.textTertiary)
            Text("暂无数据")
                .font(.system(size: 13))
                .foregroundColor(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: 卡片

    private func cardView(_ card: Model) -> some View {
        let isSelected = selection.contains(card.id)
        return HStack(alignment: .top, spacing: 0) {
            if selectMode && card.selectable {
                Button {
                    toggle(card)
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(isSelected ? Theme.primary : Theme.textTertiary)
                        .frame(width: 30, height: 30)
                }
                .padding(.leading, 4)
            }
            cardBody(card)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panelBG)
        .clipShape(RoundedCorner(radius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Theme.primary : Theme.border, lineWidth: isSelected ? 1.5 : 1)
        )
        .panelShadow()
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.35) {
            if card.selectable, !selectMode {
                selectMode = true
                toggle(card)
            }
        }
    }

    // 类型别名便于内部引用
    private typealias Model = MobileCardModel

    private func cardBody(_ card: Model) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color(hex: 0xF3F4F6)).frame(width: 34, height: 34)
                    Text(card.initials.isEmpty ? String(card.title.prefix(1)) : card.initials)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(hex: 0x374151))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.text)
                        .lineLimit(1)
                    if !card.subtitle.isEmpty {
                        Text(card.subtitle)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if selectMode && card.selectable {
                    Button {
                        toggle(card)
                    } label: {
                        Image(systemName: selection.contains(card.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18))
                            .foregroundColor(selection.contains(card.id) ? Theme.primary : Theme.textTertiary)
                    }
                } else if card.showBadge {
                    StatusTag(text: card.badgeText, kind: card.badgeKind)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)

            if !card.fields.isEmpty {
                Rectangle().fill(Color(hex: 0xF3F4F6)).frame(height: 1)
                    .padding(.horizontal, 12)
                let pairs = stride(from: 0, to: card.fields.count, by: 2).map {
                    Array(card.fields[$0..<min($0 + 2, card.fields.count)])
                }
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(pairs.indices, id: \.self) { row in
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(pairs[row]) { field in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(field.label)
                                        .font(.system(size: 10))
                                        .foregroundColor(Theme.textTertiary)
                                    Text(field.value.isEmpty ? "-" : field.value)
                                        .font(.system(size: 12))
                                        .foregroundColor(Theme.text)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            // 补齐偶数列
                            if pairs[row].count == 1 {
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                .padding(12)
            }

            if !card.actions.isEmpty {
                Rectangle().fill(Color(hex: 0xF3F4F6)).frame(height: 1)
                    .padding(.horizontal, 12)
                HStack(spacing: 0) {
                    ForEach(card.actions) { action in
                        Button {
                            action.handler()
                        } label: {
                            Text(action.title)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(action.role == .danger ? Theme.danger : Theme.linkBlue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                        }
                        if action.id != card.actions.last?.id {
                            Rectangle().fill(Color(hex: 0xF3F4F6)).frame(width: 1, height: 14)
                        }
                    }
                }
            }
        }
    }

    // MARK: 多选

    private func toggle(_ card: Model) {
        guard card.selectable else { return }
        if selection.contains(card.id) {
            selection.remove(card.id)
        } else {
            selection.insert(card.id)
        }
    }

    private var selectHeader: some View {
        HStack(spacing: 12) {
            Button("取消") {
                selection.removeAll()
                selectMode = false
            }
            .font(.system(size: 13))
            .foregroundColor(Theme.textSecondary)
            Spacer()
            Text("已选 \(selection.count) 项")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Theme.text)
            Spacer()
            Button("全选") {
                selection = Set(cards.filter(\.selectable).map(\.id))
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(Theme.linkBlue)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }

    private var batchBar: some View {
        HStack(spacing: 10) {
            ForEach(batchActions) { action in
                Button {
                    action.handler()
                } label: {
                    Text(action.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(action.role == .danger ? Theme.danger : Color(hex: 0x374151))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.panelBG)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(action.role == .danger ? Color(hex: 0xFCA5A5) : Theme.border, lineWidth: 1)
                        )
                }
                .disabled(selection.isEmpty)
                .opacity(selection.isEmpty ? 0.5 : 1)
            }
            Button {
                selection.removeAll()
                selectMode = false
            } label: {
                Text("完成")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.primary)
                    .clipShape(RoundedCorner(radius: 8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.white.opacity(0.98))
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    // MARK: 加载更多

    private var footer: some View {
        Group {
            if hasMore, let onLoadMore {
                HStack(spacing: 8) {
                    if loadingMore {
                        ProgressView().scaleEffect(0.8)
                    }
                    Text(loadingMore ? "正在加载..." : "上拉加载更多")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .onAppear {
                    guard !loadingMore else { return }
                    loadingMore = true
                    Task {
                        await onLoadMore()
                        loadingMore = false
                    }
                }
            } else if !cards.isEmpty {
                Text("共 \(total) 条 · 已全部加载")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
        }
    }
}

// MARK: - FAB（新增）

struct MobileFAB: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 50, height: 50)
                .background(Theme.primary)
                .clipShape(Circle())
                .panelShadow()
        }
    }
}

// MARK: - 底部弹层容器（详情 / 编辑 / 新增；内层自滚动，容器不重复包 ScrollView）

struct MobileSheetContainer<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack {
            content
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle(title)
        }
        .presentationDetents([.large])
    }
}
