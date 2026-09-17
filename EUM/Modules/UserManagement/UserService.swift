import Foundation

// MARK: - 用户管理模块 · 服务契约
// 模块内只依赖协议；具体实现（真实 API / 内存 Mock）由 AppEnvironment 注入。
// 好处：SwiftUI 预览与单元测试可直接注入 Mock，模块可被独立删除而不影响其他模块。

protocol UserServiceProtocol {
    func page(page: Int, size: Int, username: String, phone: String, status: Int?) async throws -> PageResult<SysUser>
    func detail(id: Int) async throws -> SysUser
    func insert(_ user: SysUser, password: String) async throws
    func update(_ user: SysUser) async throws
    func setStatus(id: Int, status: Int) async throws
    func delete(ids: [Int]) async throws
    func resetPassword(ids: [Int], newPassword: String) async throws
    /// 单用户重置（§4.23 POST /eum_rbac_user/password）
    func resetPassword(id: Int, oldPassword: String?, newPassword: String) async throws
}

// MARK: - 真实实现（委托 Core 数据层）

struct UserService: UserServiceProtocol {
    let data: DataService

    func page(page: Int, size: Int, username: String, phone: String, status: Int?) async throws -> PageResult<SysUser> {
        try await data.userPage(page: page, size: size, username: username, phone: phone, status: status)
    }

    func detail(id: Int) async throws -> SysUser {
        try await data.userDetail(id: id)
    }

    func insert(_ user: SysUser, password: String) async throws {
        try await data.userInsert(user, password: password)
    }

    func update(_ user: SysUser) async throws {
        try await data.userUpdate(user)
    }

    func setStatus(id: Int, status: Int) async throws {
        try await data.userStatus(id: id, status: status)
    }

    func delete(ids: [Int]) async throws {
        try await data.userDelete(ids: ids)
    }

    func resetPassword(ids: [Int], newPassword: String) async throws {
        try await data.userResetPassword(ids: ids, newPassword: newPassword)
    }

    func resetPassword(id: Int, oldPassword: String?, newPassword: String) async throws {
        try await data.userResetPassword(id: id, oldPassword: oldPassword, newPassword: newPassword)
    }
}

// MARK: - 内存 Mock（预览 / 单元测试 / -useMocks 演示模式）

@MainActor
final class UserManagementMockService: UserServiceProtocol {
    private var store: [SysUser]
    private var nextID: Int

    init(seed: Int = 23) {
        nextID = seed + 1
        store = (1...seed).map { i in
            var u = SysUser(id: i, username: "user\(String(i).leftPad(2, "0"))", nickName: "示例用户 \(i)")
            u.phone = "138\(String(0000 + i).leftPad(4, "0"))\(String(5678))"
            u.email = "user\(i)@eum.dev"
            u.status = i % 5 == 0 ? 0 : 1
            u.deptId = 100 + i % 3
            u.createTime = "2026-0\(i % 9 + 1)-1\(i % 9) 09:3\(i % 10):00"
            return u
        }
    }

    func page(page: Int, size: Int, username: String, phone: String, status: Int?) async throws -> PageResult<SysUser> {
        try await Task.sleep(nanoseconds: 300_000_000) // 模拟网络延迟，便于验证 loading 态
        var rows = store
        if !username.isEmpty { rows = rows.filter { $0.username.localizedCaseInsensitiveContains(username) } }
        if !phone.isEmpty { rows = rows.filter { $0.phone.contains(phone) } }
        if let status { rows = rows.filter { $0.status == status } }
        let start = (page - 1) * size
        guard start < rows.count else { return PageResult(content: [], total: rows.count) }
        let slice = Array(rows[start..<min(start + size, rows.count)])
        return PageResult(content: slice, total: rows.count)
    }

    func detail(id: Int) async throws -> SysUser {
        guard let u = store.first(where: { $0.id == id }) else { throw MockError("user not found") }
        return u
    }

    func insert(_ user: SysUser, password: String) async throws {
        var u = user
        u.id = nextID
        nextID += 1
        store.insert(u, at: 0)
    }

    func update(_ user: SysUser) async throws {
        guard let idx = store.firstIndex(where: { $0.id == user.id }) else { throw MockError("user not found") }
        store[idx] = user
    }

    func setStatus(id: Int, status: Int) async throws {
        guard let idx = store.firstIndex(where: { $0.id == id }) else { throw MockError("user not found") }
        store[idx].status = status
    }

    func delete(ids: [Int]) async throws {
        store.removeAll { ids.contains($0.id) }
    }

    func resetPassword(ids: [Int], newPassword: String) async throws {}

    func resetPassword(id: Int, oldPassword: String?, newPassword: String) async throws {}
}

private extension String {
    func leftPad(_ length: Int, _ token: Character) -> String {
        String(repeating: token, count: max(0, length - count)) + self
    }
}
