import SwiftUI

// MARK: - 用户管理模块 · ViewModel（MVVM + Observation）
// View 只负责渲染与转场；数据状态与业务编排收敛于此。
// 服务通过 UserServiceProtocol 注入（真实 API / Mock），错误以 throws 抛给 View 转 Toast。

@Observable
@MainActor
final class EumUserViewModel {
    // 查询条件（Binding 由 View 建立）
    var username = ""
    var phone = ""
    var status: Int?

    // 分页
    var page = 1
    var pageSize = 10

    // 列表数据
    private(set) var rows: [SysUser] = []
    private(set) var total = 0
    private(set) var loading = false

    // 多选（桌面复选框 + 移动端长按多选共用）
    var selected: Set<Int> = []

    var hasMore: Bool { !rows.isEmpty && rows.count < total }
    var filterCount: Int { (phone.isEmpty ? 0 : 1) + (status == nil ? 0 : 1) }

    private let service: UserServiceProtocol

    init(service: UserServiceProtocol = AppEnvironment.shared.users) {
        self.service = service
    }

    /// 加载当前页；append = 移动端上拉追加
    func load(append: Bool = false) async throws {
        loading = true
        defer { loading = false }
        let result = try await service.page(page: page, size: pageSize, username: username, phone: phone, status: status)
        rows = append ? rows + result.content : result.content
        total = result.total
        if !append { selected.removeAll() }
    }

    /// 加载下一页（失败自动回退页码）
    func loadMore() async throws {
        guard !loading, hasMore else { return }
        page += 1
        do {
            try await load(append: true)
        } catch {
            page -= 1
            throw error
        }
    }

    func resetFilters() {
        username = ""
        phone = ""
        status = nil
    }

    func clearSelection() {
        selected.removeAll()
    }

    /// 启停用户；本地先行合并，避免整页刷新
    func setStatus(_ user: SysUser, on: Bool) async throws {
        try await service.setStatus(id: user.id, status: on ? 1 : 0)
        var updated = user
        updated.status = on ? 1 : 0
        rows = rows.map { $0.id == user.id ? updated : $0 }
    }

    func batchDelete() async throws {
        try await service.delete(ids: Array(selected))
        selected.removeAll()
    }

    func resetPassword(for ids: [Int], newPassword: String) async throws {
        try await service.resetPassword(ids: ids, newPassword: newPassword)
    }

    func resetPassword(id: Int, newPassword: String) async throws {
        try await service.resetPassword(id: id, oldPassword: nil, newPassword: newPassword)
    }
}
