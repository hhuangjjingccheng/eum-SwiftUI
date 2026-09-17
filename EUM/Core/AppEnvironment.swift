import Foundation

// MARK: - 轻量 DI 容器
// 模块间不直接依赖实现：View / ViewModel 只认识协议，实现由这里装配。
// 新模块的接入方式：定义 XxxServiceProtocol + 真实/Mock 实现，在这里暴露一个依赖项。

@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    /// 用户管理模块服务
    let users: UserServiceProtocol

    private init() {
        // -useMocks 启动参数：所有已迁移模块注入内存 Mock
        // 用途：SwiftUI 预览、UI 自动化验证、后端不可用时的演示
        let useMocks = ProcessInfo.processInfo.arguments.contains("-useMocks")
        users = useMocks ? UserManagementMockService() : UserService(data: DataService.shared)
    }
}
