import SwiftUI

// MARK: - 树形表格（部门/菜单管理用）

struct TreeRow<T: Identifiable>: View {
    let depth: CGFloat
    let isExpanded: Bool
    let hasChildren: Bool
    let onToggle: (() -> Void)?
    let content: [TableColBuild]

    var body: some View { EmptyView() }
}

typealias TableColBuild = (String, CGFloat?, TextAlignment)

/// 通用树彧行布局：缩进 + 展开箭头 + 单元格
struct TreeCellsRow: View {
    let columns: [TableCol]
    let cells: [TableCell]
    let depth: Int
    var indentUnit: CGFloat = 16
    var hasChildren: Bool = false
    var isExpanded: Bool = false
    var onToggle: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { idx, cell in
                if idx == 0 {
                    HStack(spacing: 4) {
                        if hasChildren {
                            Button {
                                onToggle?()
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(Theme.textSecondary)
                                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Color.clear.frame(width: 20, height: 1)
                        }
                        cell
                    }
                    .padding(.leading, CGFloat(depth) * indentUnit + 4)
                } else {
                    cell
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// 树形单元格便捷构造
func treeCell(_ text: String, width: CGFloat?, align: TextAlignment = .leading, mono: Bool = false, color: Color = Theme.text) -> TableCell {
    TableCell(text: text, width: width, align: align, mono: mono, color: color)
}

// MARK: - 展开状态容器

@MainActor
final class TreeExpansion: ObservableObject {
    @Published var expanded: Set<Int> = []

    func toggle(_ id: Int) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    func expandAll(_ ids: [Int]) { expanded = Set(ids) }
    func collapseAll() { expanded = [] }
}

// MARK: - 菜单勾选树（角色授权）

struct MenuCheckTree: View {
    let menus: [SysMenu]
    @Binding var checked: Set<Int>
    var showTypeBadge: Bool = true

    /// 全部可选节点 id（含按钮）
    private var allIds: Set<Int> {
        Set(menus.flatMap { $0.flattenedMenuIds() })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(menus.sorted { $0.orderNum < $1.orderNum }) { menu in
                MenuCheckNode(menu: menu, checked: $checked, showTypeBadge: showTypeBadge)
            }
        }
        .padding(.vertical, 6)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
    }
}

private extension SysMenu {
    func flattenedMenuIds() -> [Int] {
        [id] + children.flatMap { $0.flattenedMenuIds() }
    }
}

private struct MenuCheckNode: View {
    let menu: SysMenu
    @Binding var checked: Set<Int>
    var showTypeBadge: Bool
    @State private var expanded = true

    /// 子级全部勾选 → 父级半选/全选状态
    private var childIds: [Int] { menu.children.flatMap { $0.flattenedMenuIds() } }
    private var allChildrenChecked: Bool { !childIds.isEmpty && childIds.allSatisfy { checked.contains($0) } }
    private var someChildrenChecked: Bool { childIds.contains { checked.contains($0) } }
    private var selfChecked: Bool { checked.contains(menu.id) }
    private var displayState: (on: Bool, mixed: Bool) {
        if !menu.children.isEmpty {
            return (allChildrenChecked, someChildrenChecked && !allChildrenChecked)
        }
        return (selfChecked, false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                if !menu.children.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 14, height: 1)
                        .padding(.leading, menu.menuType == 3 ? 18 : 0)
                }

                Button {
                    toggleCheck()
                } label: {
                    HStack(spacing: 6) {
                        checkBox
                        Text(menu.menuName)
                            .font(.system(size: 12.5))
                            .foregroundColor(Theme.text)
                        if showTypeBadge {
                            StatusTag(
                                text: menu.menuTypeText,
                                kind: menu.menuType == 1 ? .primary : (menu.menuType == 2 ? .success : .warning)
                            )
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 5)
            .padding(.trailing, 8)

            if expanded && !menu.children.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(menu.children.sorted { $0.orderNum < $1.orderNum }) { child in
                        MenuCheckNode(menu: child, checked: $checked, showTypeBadge: showTypeBadge)
                    }
                }
                .padding(.leading, 22)
            }
        }
    }

    private var checkBox: some View {
        Group {
            if displayState.on {
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.primary).frame(width: 14, height: 14)
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundColor(.white)
                }
            } else if displayState.mixed {
                ZStack {
                    RoundedRectangle(cornerRadius: 3).fill(Theme.primary).frame(width: 14, height: 14)
                    Rectangle().fill(.white).frame(width: 8, height: 2)
                }
            } else {
                RoundedRectangle(cornerRadius: 3).stroke(Theme.primaryLight5, lineWidth: 1).frame(width: 14, height: 14)
            }
        }
    }

    /// 勾选/取消：级联全部子孙
    private func toggleCheck() {
        let ids = menu.flattenedMenuIds()
        if displayState.on || displayState.mixed {
            ids.forEach { checked.remove($0) }
        } else {
            ids.forEach { checked.insert($0) }
        }
    }
}

// MARK: - 树形选择器（上级部门/上级菜单，对应 el-tree-select）

struct TreePickerSheet<T: Identifiable & Hashable>: View {
    let title: String
    let rootLabel: String
    @Binding var selection: T?
    @Environment(\.dismiss) private var dismiss
    let children: (T) -> [T]
    let label: (T) -> String
    let value: (T) -> Int

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        selection = nil
                        dismiss()
                    } label: {
                        Text(rootLabel)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(selection == nil ? Theme.primary : Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .background(selection == nil ? Theme.borderLight : .clear)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }.font(.system(size: 13))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
