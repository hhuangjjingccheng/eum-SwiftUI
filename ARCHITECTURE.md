# EUM SwiftUI 架构指南（模块化 / MVVM / DI）

> 本文档描述目标架构与迁移状态。新增代码必须遵循本文约定；存量代码按「迁移状态」逐步收敛。

## 1. 目录结构（按功能划分的模块）

```
EUM/
├── App/                        # 入口（EUMApp / RootView）
├── Core/                       # 共享内核（跨模块基础设施）
│   ├── AppState.swift          #   全局会话 + 中心化路由（AppRoute / navigate / 页签）
│   ├── AppEnvironment.swift    #   DI 容器：装配各模块服务协议的真实 / Mock 实现
│   ├── API/                    #   APIClient（网络 / SSE / I18n）、DataService（数据层）、L10n
│   └── Models*.swift           #   领域模型
├── Layout/                     # 主布局（MainLayout：侧栏 / 顶栏 / 页签 / 抽屉 / 路由出口）
├── Modules/                    # ★ 业务模块（每个模块是独立闭环，可整体删除）
│   ├── Shared/                 #   共享组件库：Wire 组件、MobileKit、Theme、Icons、L10nTables
│   ├── UserManagement/         #   EumUserView + EumUserViewModel + UserService(协议/真实/Mock)
│   ├── RoleAndPost/  DeptAndMenu/  Dictionary/  Settings/  Account/  AIConfig/
│   ├── DataPermission/  FXShell/  Biz/  Uralyt/  AppModules/  Tool/  Chat/
│   ├── Auth/  Profile/  Dashboard/  Welcome/  Common/
└── EUM.xcodeproj               # 由 project.yml 经 xcodegen 生成（增删文件后执行 `xcodegen generate`）
```

**模块标准**：一个模块 = `View + ViewModel + Service(协议/真实/Mock)` 的闭环；删除整个模块目录后，其余模块不受影响（路由表中移除对应 case 即可）。

## 2. 分层与依赖规则

```
View ──(状态绑定)──▶ ViewModel ──(协议)──▶ ServiceProtocol ◀──实现── DataService / Mock
 │                    │
 └── @EnvironmentObject AppState（路由 / 会话 / Toast，横切设施）
```

- **View**：只渲染。导航/弹窗等页面内 UI 状态留在 View；数据状态全部在 ViewModel。
- **ViewModel**：`@Observable + @MainActor`；业务编排；错误以 `throws` 抛出，由 View 转 Toast。
- **Service 协议**：模块内定义（如 `UserServiceProtocol`），真实实现委托 `DataService`，Mock 为内存数据。
- **DI**：`AppEnvironment.shared` 装配；View 以默认参数注入：
  `EumUserView(service: AppEnvironment.shared.users)`；`-useMocks` 启动参数可全局切换 Mock。
- **路由**：中心化 `AppRoute` + `AppState.navigate(to:)`，模块内禁止硬编码跳转。

## 3. MVVM 与状态管理

- 新代码一律使用 **`@Observable`**（Observation 框架，细粒度刷新），不再新增 `ObservableObject` 业务对象。
- 生命周期：ViewModel 由 View 的 `@State` 持有（`_viewModel = State(initialValue:)` 注入服务）；
  子视图需要绑定时用 `@Bindable` 或直接传 `$viewModel.xxx`。
- 全局会话/路由/Toast 仍是 `AppState`（`@EnvironmentObject`），属于横切设施，不承载业务数据。

## 4. 性能约定

- 列表：卡片流使用 `LazyVStack`（MobileCardList）；桌面 WireTable 因固定列宽对齐需要，保持分页内 eager 渲染（每页 ≤50 行）。
- 禁止在 `body` / 主线程做耗时操作：网络与 JSON 解析统一在 `APIClient` 的 async 通道；需要后台计算用 `Task.detached` + `@MainActor` 回写。
- 视图拆分：复杂页面按 `headerSection / listSection / ...` 子视图组合，避免巨型 body。

## 5. 迁移状态

| 模块 | View | ViewModel(@Observable) | Service 协议 + Mock |
|---|---|---|---|
| UserManagement | ✅ | ✅ EumUserViewModel | ✅ UserService / UserManagementMockService |
| Dashboard | ✅ | ✅ DashboardViewModel | —（无网络依赖） |
| Settings / Auth / Chat / 其余列表模块 | ✅（已模块化） | ⏳ 待迁移（沿用 AppState + DataService） | ⏳ 待迁移 |

> 迁移一个存量模块的步骤：① 在模块目录建 `XxxServiceProtocol`（从 DataService 抽取用到的端点）+ 真实/Mock 实现；② 建 `XxxViewModel` 搬迁数据状态与业务函数；③ View 删除对应 `@State`，改为 `$viewModel.*` 绑定；④ 在 `AppEnvironment` 注册；⑤ 更新本文档状态表。
