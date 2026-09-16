# EUM SwiftUI

以 `eum-front`（Vue 3 + Element Plus 中后台）为标准，使用 SwiftUI 实现的 EUM 管理系统原生客户端。**已完成后端接口对接**，对接 `http://localhost:9000`（与 eum-front 的 vite 代理目标一致），登录账号与 Web 端通用。

**平台支持**：iPhone / iPad / **Mac（Catalyst）**，一套代码三端三风格。

- **iPhone**（compact 尺寸）：**第三套 UI 风格（Mobile 卡片流）**——横滚表格重构为信息卡片，查询表单收进「筛选」底部弹层，长按卡片进入多选 + 底部批量操作栏，FAB 新增，上拉加载更多；详情/编辑以底部弹层呈现。组件库见 `EUM/Core/MobileKit.swift`
- **iPad / Mac**（regular 尺寸）：线框（Wireframe）双栏布局，侧边栏常驻；Dashboard 统计卡与授权单卡片自适应多列网格；个人中心左右分栏
- 三端共用同一设计基因：主色 `#171717`、页面底 `#F9FAFB`、深色表头 `#1F2937`、斑马纹、胶囊页签；切换只按 `horizontalSizeClass`，桌面端零改动
- Mac 端使用 Mac Catalyst（工程已开启 `SUPPORTS_MACCATALYST`，签名方式为 "Sign to Run Locally" ad-hoc，无需开发者账号即可本地运行）

## 运行要求

- macOS + Xcode（建议 26.x，最低 Xcode 15 / iOS 17 SDK）
- iOS 17.0+ 模拟器或真机

## 打开与运行

1. 双击打开 `EUM.xcodeproj`（由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 从 `project.yml` 生成）。
2. 顶部选择 `EUM` scheme 与任一 iOS 模拟器（如 iPhone 17 Pro）。
3. `Cmd + R` 运行。

> 如需调整 target/设置，修改 `project.yml` 后执行 `xcodegen generate` 重新生成工程。

命令行构建：

```bash
xcodebuild -project EUM.xcodeproj -scheme EUM \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## 登录与后端

- 登录走真实接口 `POST /auth/login`（如 `admin / Hyzn@2001`）；登录后自动拉取 `/auth/info`（用户信息 + 菜单树）、`/sys/config`（主题 / 多语言 i18n 表）、角色 / 岗位 / 部门 / `eum_status` 字典等基础数据。
- 后端地址在 `EUM/Core/API/APIClient.swift` 的 `baseURL` 修改（默认 `http://localhost:9000`，Info.plist 已允许 HTTP）。
- 侧边栏菜单完全由后端菜单树驱动：menuName 按 languageJson 做 i18n 翻译；`component` 映射到原生页面；未实现的组件显示「页面开发中」；`http(s)://` 组件用 Safari 打开；按钮型菜单不显示。
  - 已映射：`eum/user|account|role|menu|dept|post|dict|config|ai/index`、`eum/fxshell/index`（兼容 `bovinishell/index`）、`eum/dataPermission/index`、`eum/auditLog/index`、`biz/customer/index`、`biz/order/index`、`tool/calcite/index`、`tool/langgraph/index`、`uralyt-u/user|uric|medical/index`、`Chat`、`app/license|device|plugin/index`。
- 所有列表页的查询 / 分页 / 新增 / 编辑 / 详情 / 删除 / 批量删除 / 状态开关 / 重置密码均为真实接口调用；脱敏字段（手机号 / 邮箱含 `*`）提交时自动剥离（对齐 Web 端逻辑）。
- 智能对话对接 `GET /chat/models`（模型列表）与 `GET /chat/stream`（SSE 流式回复，`data:` 行协议）。
- Token 持久化于 UserDefaults；401 自动清除会话并回到登录页。
- 「忘记密码 / 设备授权申请」前端流程与 Web 端一致（申请提交为真实接口）。

## 页面清单（对照 eum-front）

| 模块 | 页面 |
|---|---|
| 框架 | 登录 / 注册 / 忘记密码 / 欢迎页 / 仪表盘 / 个人中心 / AI 助手浮窗 / 404 / 403 / 页面开发中 |
| 系统管理 | 用户管理、角色管理、菜单管理、部门管理、岗位管理、字典管理、参数设置、AI 配置 |
| 安全与审计 | 数据权限（规则 + 授权 / 例外）、审计日志（数据访问 / 权限变更） |
| 业务管理 | 客户管理、订单管理、账号管理 |
| 开发者工具 | 数据查询（Calcite 跨库 SQL 调试）、LangGraph 线程调试台 |
| 友来特数据 | 患者用户、尿酸记录、用药记录 |
| AI 助手 | 智能对话（会话列表 + Mock 流式回复 + 模型选择） |
| 应用管理 | 授权管理（卡片网格 + 颁发/吊销/查看设备）、设备管理（绑定/解绑/重绑）、插件市场、设备授权申请（免登录独立页） |
| 工具 | FXShell 异常管理（bovinishell，异常上报 + 修复标记） |

## 与后端协议对齐（`eum/doc/API对接文档.md`）

对接层已按文档 §2 / §6 逐条校准：

- **统一响应体**：业务成败只看 `code`（200 成功）；非 2xx 的 HTTP 状态码仅按网关异常处理并给出兜底文案。
- **鉴权错误码**：`4011`~`4015`（兼容网关裸 `401`）统一识别为会话失效 → 清除会话回登录页；`APIClient.ApiError.isAuthFailure` 可直接判定。
- **Token 静默续期**：命中鉴权码时自动调用 `POST /auth/refresh`（并发请求合并为一次）并重放原请求，续期失败才登出。
- **分页约定**：入参 `pageNum` 从 1 开始；出参解析 `content / totalElements / totalPages / number / size`（`PageResult` 已暴露元信息）。
- **错误码文案**：后端未返回 `message` 时按 §6 错误码表兜底；`1001~1004 / 1027~1028` 标记为「内置数据保护」，`isProtectedResource` 供界面禁用操作。
- **非信封响应**：`langgraph` 等直接返回 `Map` 的接口按原始对象返回，不做 `data` 拆解。

## 接口覆盖

按 `eum/doc/api-endpoints.json` 静态比对，已对接 **159 / 181** 个端点（88%；按路径参数占位符差异归一后约 96%）。

本轮补齐：`bovinishell` 全套、部门 / 菜单的 `page / detail / delete / status`、用户 `detail / password`、字典 `detail / getDictDataByType`、AI 配置 `list / getById`、岗位 `getById`、友来特 `getById`、`account` 全套、`biz_customer`、`biz_order`、`eum_data_permission_rule / grant / exception`、`eum_log_data_access / permission_change`、`auth/login/phone`、`api/calcite`（health / datasources / schemas / execute）、`langgraph` 全套（含 POST SSE streamRun）、`eum_rbac_role_menu|role_dept|user_role` 关联表。

尚未对接（按设计取舍）：

| 模块 | 端点 | 说明 |
|---|---|---|
| `api/calcite` v1 | `query / update / datasource` | 旧版接口，v2 `execute` 已覆盖动态 SQL |
| `api/calcite/v2/example/*` | 4 | 后端演示用示例接口，非管理功能 |
| `index/jgongling` | 1 | 服务端首页模板跳转 |

> 说明：`eum_rbac_role_menu|role_dept|user_role` 的 `*Save` 覆盖式保存方法已就绪，用于「增量授权」场景；日常新增/编辑仍由 `eum_rbac_role|user` 的批量字段一次提交。
> `LangGraph` 页的 run 请求体为自由 Map，以原始 JSON 编辑区透传（input / assistant_id / stream_mode 等）。


设计还原要点：

- 后台内页为「线框（Wireframe）」风格：主色 `#171717`、页面底 `#F9FAFB`、深色表头 `#1F2937`、斑马纹表格、胶囊动态页签（激活黑底白点）。
- 认证页为 IBM Carbon 风格：主蓝 `#0F62FE`、灰底输入框 `#F2F4F8` 仅底部描边、Google/Apple 描边按钮。
- RBAC 页面遵循 eum-front 的「动态页签」架构：新增/编辑/详情以页签打开而非弹窗；应用管理与友来特模块按原版使用弹窗（sheet）。
- 状态开关带二次确认；批量删除/删除/吊销均有确认弹窗；操作结果以 Toast 提示。

## 工程结构

```
eum-SwiftUI/
├── project.yml            # XcodeGen 工程定义
├── tools/
│   └── xcode_add_sources.py  # 无 xcodegen 时向 EUM.xcodeproj 注入源文件的脚本
├── EUM.xcodeproj          # 生成产物（勿手改）
└── EUM/
    ├── App/               # 入口 + 根视图
    ├── Core/
    │   ├── Theme.swift          # 设计变量（颜色/字体/阴影）
    │   ├── Icons.swift          # svg 图标名 → SF Symbol 映射
    │   ├── Models.swift         # 实体模型（含后端 JSON 字段映射）
    │   ├── Models+Business.swift # 业务模型（FXShell / 客户 / 订单 / 数据权限 / 审计日志）
    │   ├── AppState.swift       # 会话/路由/标签页/Toast 全局状态
    │   ├── Wire.swift           # 线框组件库（WireCard/WireTable/页签/分页/表单/Toast…）
    │   ├── TreeComponents.swift # 树形表格/勾选树
    │   └── API/
    │       ├── APIClient.swift  # HTTP 客户端（统一响应/鉴权码/自动续期/SSE）+ i18n
    │       ├── DataService.swift # 数据服务层（对齐 eum-front src/api/** 全部端点）
    │       └── DataService+Modules.swift # 补充端点（业务/权限/审计/设备侧）
    ├── Layout/MainLayout.swift  # 主框架（侧边栏+顶栏+TagsView+路由工厂）
    └── Features/
        ├── Auth/            # 登录/注册/忘记密码/设备授权申请
        ├── Biz/             # 客户管理/订单管理
        ├── Misc/            # Dashboard/欢迎页/404/403/开发中
        ├── Profile/         # 个人中心
        ├── Chat/            # 智能对话（SSE 流式）
        ├── System/          # 系统管理 8 页 + FXShell + 数据权限 + 审计日志
        ├── Uralyt/          # 友来特 3 页
        └── App/             # 应用管理 3 页
```

### 新增源文件（本机未装 xcodegen 时）

`EUM.xcodeproj` 的文件列表是静态的——新增 `.swift` 后必须登记到工程，否则不会参与编译：

```bash
python3 tools/xcode_add_sources.py EUM/Features/Biz/BizViews.swift
```

脚本会自动新建缺失的中间 Group（如 `Features/Biz`），并同步 `PBXFileReference / PBXBuildFile / PBXGroup.children / PBXSourcesBuildPhase` 四处，插入顺序按文件名排序，与 XcodeGen 生成结果一致。装了 xcodegen 时改用 `xcodegen generate` 即可。


## 自动化验证用启动参数

`simctl launch` 支持以下参数（仅用于调试/自动化截图）：

```bash
# 直接打开指定页面（可选值见 AppRoute）
xcrun simctl launch <device> com.eum.swiftui -skipLogin -route eumUser

# 携带已登录 token 启动（跳过登录页，自动恢复会话）
xcrun simctl launch <device> com.eum.swiftui -eumToken "<jwt>"
```

- `-skipLogin`：跳过登录直接进入主界面
- `-route <route>`：直接打开指定页面，可选值见 `AppRoute`（如 `dashboard`、`eumUser`、`eumDict`、`eumFxshell`、`eumDataPermission`、`eumAuditLog`、`bizCustomer`、`bizOrder`、`appLicense`、`chat`、`userInfo`…）
- `-eumToken <jwt>`：注入会话 token（模拟登录后的启动状态）

## 命令行构建

```bash
# iPhone 模拟器
xcodebuild -project EUM.xcodeproj -scheme EUM \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build build

# iPad 模拟器
xcodebuild -project EUM.xcodeproj -scheme EUM \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' \
  -derivedDataPath build build

# Mac Catalyst
xcodebuild -project EUM.xcodeproj -scheme EUM \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO build

# 产物：
#   build/Build/Products/Debug-iphonesimulator/EUM.app
#   build/Build/Products/Debug-maccatalyst/EUM.app（本机直接运行前执行：
#   codesign --force --deep --sign - <app 路径>）
```

> Xcode GUI 中运行 Mac 版：目标设备选择 **My Mac (Mac Catalyst)**，签名选择 **Sign to Run Locally**（工程默认已配置，无需开发者账号）。
