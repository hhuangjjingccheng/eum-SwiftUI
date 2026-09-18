import Foundation

// MARK: - API 客户端（对齐 eum/doc/API对接文档.md §2 全局约定 / §6 错误码）

/// §2.1 **所有接口 HTTP 状态码恒为 200**，业务成败由 `code` 判定（200 成功）。
/// §2.3 Token 失效返回 `4011`~`4015`，对接方应清除 token 并跳转登录页。
/// 非 2xx 的 HTTP 状态码仅出现在网关/容器层异常（服务未启动、502/504）。
final class APIClient: @unchecked Sendable {
    static let shared = APIClient()

    /// 后端地址（eum-front 经 vite 代理 /api → 127.0.0.1:9000 并重写去前缀，此处直连）
    var baseURL = URL(string: "http://localhost:9000")!

    /// JWT Token（与 web 端 localStorage.token 等价；支持 -eumToken <token> 启动参数注入）
    private let lock = NSLock()
    private var _token: String? = {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-eumToken"), i + 1 < args.count {
            return args[i + 1]
        }
        return UserDefaults.standard.string(forKey: "eum.api.token")
    }()

    var token: String? { lock.withLock { _token } }

    /// 语言（Accept-Language）
    var language = "zh-CN"

    /// 401 时回调（清登录态）
    var onUnauthorized: (() -> Void)?

    enum HTTPMethod: String {
        case get = "GET", post = "POST", put = "PUT", delete = "DELETE"
    }

    struct ApiError: LocalizedError {
        let code: Int
        let message: String

        var errorDescription: String? { message }
        /// §6 鉴权类：需清除会话并回登录页
        var isAuthFailure: Bool { APIClient.isAuthCode(code) }
        /// 网关/网络类（HTTP 状态码透传）：可重试
        var isTransient: Bool { code < 0 || (code >= 500 && code < 1000) }
        /// §6 内置数据保护类：界面应直接禁用对应操作（超级管理员不可删/改）
        var isProtectedResource: Bool { APIClient.protectedCodes.contains(code) }
    }

    // MARK: 错误码表（§6）

    static let successCode = 200
    /// 4011~4015 + 网关层裸 401（兼容）
    static let authCodes: Set<Int> = [401, 4011, 4012, 4013, 4014, 4015]
    /// §6 内置数据保护
    static let protectedCodes: Set<Int> = [1001, 1002, 1003, 1004, 1027, 1028]

    static func isAuthCode(_ code: Int) -> Bool { authCodes.contains(code) }

    /// 业务码 → 兜底文案（后端未返回 message 时使用）
    static func fallbackMessage(_ code: Int) -> String? {
        switch code {
        case 500: return "系统未知错误，请稍后重试"
        case 1001: return "不允许修改超级管理员状态"
        case 1002: return "不允许修改超级管理员角色状态"
        case 1003: return "不允许删除超级管理员用户"
        case 1004: return "不允许删除超级管理员角色"
        case 1005: return "原密码错误"
        case 1006: return "字典类型不存在"
        case 1007: return "字典类型已存在"
        case 1008: return "客户不存在"
        case 1009: return "密码不能为空"
        case 1010: return "手机号已存在"
        case 1011: return "权限标识已存在"
        case 1012: return "用户不存在"
        case 1013: return "用户名已存在"
        case 1014: return "系统未配置默认 AI 密钥，请在系统设置中配置"
        case 1015: return "绑定的 AI 服务商不存在或已禁用"
        case 1016: return "联系电话已存在"
        case 1017: return "获取模式列表失败"
        case 1018: return "菜单不存在"
        case 1019: return "角色不存在"
        case 1020: return "角色权限字符串已存在"
        case 1021: return "订单不存在"
        case 1022: return "订单号已存在"
        case 1023: return "该菜单下存在子菜单，不能删除"
        case 1024: return "该部门下存在子部门，不能删除"
        case 1025: return "账号不存在"
        case 1026: return "账号已存在"
        case 1027: return "超级管理员用户不允许编辑"
        case 1028: return "超级管理员角色不允许编辑"
        case 1029: return "邮箱已存在"
        case 1030: return "部门不存在"
        case 1031: return "配置的默认 AI 密钥不存在或已禁用"
        case 4011: return "Token 已过期，请重新登录"
        case 4012: return "Token 验证失败，请重新登录"
        case 4013: return "无有效 Token，请重新登录"
        case 4014: return "无效的 Token，请重新登录"
        case 4015: return "无法获取用户信息，请重新登录"
        default: return nil
        }
    }

    func setToken(_ token: String?) {
        lock.withLock { _token = token }
        if let token {
            UserDefaults.standard.set(token, forKey: "eum.api.token")
        } else {
            UserDefaults.standard.removeObject(forKey: "eum.api.token")
        }
    }

    // MARK: Token 静默续期（/auth/refresh，并发请求合并为一次）

    private let refresher = TokenRefreshCoordinator()

    private actor TokenRefreshCoordinator {
        private var inFlight: Task<String, Error>?

        func perform(_ work: @escaping @Sendable () async throws -> String) async throws -> String {
            if let inFlight { return try await inFlight.value }
            let task = Task { try await work() }
            inFlight = task
            defer { inFlight = nil }
            return try await task.value
        }
    }

    /// §4.4.3 刷新 JWT Token（无请求体，服务端读取 Authorization 头）
    func refreshToken() async throws -> String {
        try await refresher.perform { [weak self] in
            guard let self else { throw ApiError(code: -1, message: "客户端已释放") }
            // isRetry: true —— 续期接口自身不再触发二次续期，避免死循环
            let data = try await self.perform(.post, "auth/refresh", query: nil, body: nil, isRetry: true)
            guard let token = data as? String, !token.isEmpty else {
                throw ApiError(code: -1, message: "会话续期失败")
            }
            return token
        }
    }

    // MARK: 统一请求

    /// 统一请求：返回 data 字段（code != 200 抛错；鉴权失效先尝试续期，失败则登出）
    @discardableResult
    func request(_ method: HTTPMethod, _ path: String,
                 query: [String: String]? = nil,
                 body: [String: Any]? = nil) async throws -> Any? {
        try await perform(method, path, query: query, body: body, isRetry: false)
    }

    private func perform(_ method: HTTPMethod, _ path: String,
                         query: [String: String]?, body: [String: Any]?,
                         isRetry: Bool) async throws -> Any? {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if let query, !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method.rawValue
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(language, forHTTPHeaderField: "Accept-Language")
        if let token = self.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw Self.networkError(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ApiError(code: -1, message: "网络错误，请稍后重试")
        }

        var payload: [String: Any] = [:]
        if !data.isEmpty {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                payload = obj
            } else {
                // 非 JSON 响应（网关 HTML 错误页 / 服务未启动）
                throw ApiError(code: http.statusCode, message: Self.defaultMessage(for: http.statusCode))
            }
        } else if http.statusCode == 200 {
            // 空响应体 + HTTP 200：视为成功（部分 void 接口）
            return nil
        }

        // HTTP 层异常：仅网关/容器层会出现（§2.1）
        guard (200...299).contains(http.statusCode) else {
            let msg = (payload["message"] as? String) ?? Self.defaultMessage(for: http.statusCode)
            throw ApiError(code: http.statusCode, message: msg)
        }

        // 非信封响应（如 langgraph 直接返回 Map）：原样返回整个对象
        guard let rawCode = JV.int(payload["code"]) else {
            return payload.isEmpty ? nil : payload
        }

        if rawCode == Self.successCode { return payload["data"] }

        let message = (payload["message"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? Self.fallbackMessage(rawCode) ?? "请求失败"

        if Self.isAuthCode(rawCode) {
            // §2.3 会话失效：先尝试静默续期，续期成功则重放原请求
            if !isRetry, self.token != nil, path != "auth/refresh" {
                if let newToken = try? await refreshToken() {
                    setToken(newToken)
                    return try await perform(method, path, query: query, body: body, isRetry: true)
                }
            }
            Task { @MainActor in self.onUnauthorized?() }
            throw ApiError(code: rawCode, message: Self.fallbackMessage(rawCode) ?? message)
        }

        throw ApiError(code: rawCode, message: message)
    }

    private static func networkError(_ error: Error) -> ApiError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost:
                return ApiError(code: -1, message: "网络连接失败，请检查网络或服务地址")
            case .timedOut:
                return ApiError(code: -1, message: "请求超时，请稍后重试")
            case .cannotParseResponse, .badServerResponse:
                return ApiError(code: -1, message: "服务响应异常，请检查后端是否启动")
            default:
                return ApiError(code: -1, message: "网络请求失败，请稍后重试")
            }
        }
        return ApiError(code: -1, message: (error as? LocalizedError)?.errorDescription ?? "网络请求失败，请稍后重试")
    }

    private static func defaultMessage(for status: Int) -> String {
        switch status {
        case 400: return "请求参数错误"
        case 401: return "登录状态已过期，请重新登录"
        case 403: return "没有权限访问该资源"
        case 404: return "请求的接口或资源不存在"
        case 405: return "请求方法不允许"
        case 408: return "请求超时"
        case 500: return "服务器内部错误，请联系管理员"
        case 502: return "系统维护中 (502)"
        case 503: return "服务不可用 (503)"
        case 504: return "网关超时 (504)"
        default: return "系统未知错误 (\(status))"
        }
    }

    // MARK: 便捷封装
    @discardableResult
    func get(_ path: String, query: [String: String]? = nil) async throws -> Any? {
        try await request(.get, path, query: query)
    }

    @discardableResult
    func post(_ path: String, _ body: [String: Any]? = nil) async throws -> Any? {
        try await request(.post, path, body: body)
    }

    @discardableResult
    func put(_ path: String, _ body: [String: Any]? = nil) async throws -> Any? {
        try await request(.put, path, body: body)
    }

    @discardableResult
    func delete(_ path: String) async throws -> Any? {
        try await request(.delete, path)
    }

    // MARK: SSE（chat/stream、langgraph runs/stream）
    /// GET-SSE（旧签名保持兼容）与 POST-SSE（§4.26.6 streamRun 为 POST + SSE 响应）统一入口
    func streamSSE(method: HTTPMethod? = nil, path: String, query: [String: String]? = nil,
                   body: [String: Any]? = nil,
                   onChunk: @escaping (String) -> Void) async throws {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if let query, !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: components.url!)
        req.httpMethod = (method ?? .get).rawValue
        req.timeoutInterval = 120   // 流式响应生命周期长于普通请求
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue(language, forHTTPHeaderField: "Accept-Language")
        if let token = self.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ApiError(code: -1, message: "网络请求失败，请稍后重试")
        }
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            var data = String(line.dropFirst(5))
            if data.hasPrefix(" ") { data.removeFirst() }
            if data == "[DONE]" { continue }
            onChunk(data)
        }
    }
}

// MARK: - JSON 动态取值辅助（容错 String/Int/Double/Bool/null 混用）

enum JV {
    static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let d = v as? Double { return Int(d) }
        if let s = v as? String { return Int(s) ?? Double(s).map(Int.init) }
        if let n = v as? NSNumber { return n.intValue }
        return nil
    }

    static func double(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        if let s = v as? String { return Double(s) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }

    static func string(_ v: Any?) -> String {
        if let s = v as? String { return s }
        if let i = v as? Int { return "\(i)" }
        if let d = v as? Double {
            return d.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(d)) : "\(d)"
        }
        if let b = v as? Bool { return b ? "1" : "0" }
        return ""
    }

    static func bool(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let i = int(v) { return i != 0 }
        if let s = v as? String { return ["true", "1", "是"].contains(s.lowercased()) }
        return false
    }

    static func intArray(_ v: Any?) -> [Int] {
        guard let arr = v as? [Any] else { return [] }
        return arr.compactMap { int($0) }
    }

    static func dictArray(_ v: Any?) -> [[String: Any]] {
        if let arr = v as? [[String: Any]] { return arr }
        return []
    }

    static func dict(_ v: Any?) -> [String: Any] {
        (v as? [String: Any]) ?? [:]
    }
}

// MARK: - i18n（对齐 configStore.translate：查 languageJson，未命中原样返回）
// 取词表 = 内置兜底表（L10n.baseTables）∪ 服务端 languageJson（服务端优先），
// 保证任意环境下切换语言都有可见效果；UI 文案一律通过 I18n.t(key) 运行时取词。

enum I18n {
    /// 各语言取词表（内置兜底 ∪ 服务端配置，服务端优先）
    static private(set) var tables: [String: [String: String]] = [:]
    /// 当前语言（始终为具体语言码，"system" 已按设备解析）
    static private(set) var language = "zh-CN"

    static func apply(languageJson: [String: Any], language lang: String) {
        // 合并顺序：App 专属文案 ∪ eum-front 同源词表 ∪ 服务端 languageJson（后者优先）
        var merged = L10n.baseTables
        for (code, value) in L10n.webTables {
            var dict = merged[code] ?? [:]
            for (k, v) in value { dict[k] = v }
            merged[code] = dict
        }
        for (code, value) in languageJson {
            var dict = merged[code] ?? [:]
            if let d = value as? [String: String] {
                for (k, v) in d { dict[k] = v }
            } else if let d = value as? [String: Any] {
                for (k, v) in d { if let s = v as? String { dict[k] = s } }
            }
            merged[code] = dict
        }
        tables = merged
        language = resolve(lang, available: Array(merged.keys))
    }

    /// "system" 或缺失语言码 → 按设备首选语言在可用语言中匹配（精确 → 语言基码 → 前缀）
    static func resolve(_ code: String, available: [String]) -> String {
        guard code == "system" || !available.contains(code) else { return code }
        guard !available.isEmpty else { return code == "system" ? "zh-CN" : code }
        for preferred in Locale.preferredLanguages {
            if available.contains(preferred) { return preferred }
            let base = String(preferred.split(separator: "-").first ?? "")
            if available.contains(base) { return base }
            if let match = available.first(where: { $0.hasPrefix(String(preferred.prefix(2))) }) { return match }
        }
        return available.first ?? "zh-CN"
    }

    /// 已配置语言（含内置兜底，供设置页语言选项使用）
    static var availableLanguages: [String] { tables.keys.sorted() }

    static func t(_ key: String) -> String {
        tables[language]?[key] ?? key
    }
}

/// 运行时取词的简写门面
@inline(__always)
func L(_ key: String) -> String { I18n.t(key) }

/// MARK: - 内置兜底词表（zh-CN / en）
/// 服务端 languageJson 可覆盖同名 key；未覆盖时 UI 依然可切换中英文

enum L10n {
    static let baseTables: [String: [String: String]] = [
        "zh-CN": [
            // 路由 / 页面标题
            "route.welcome": "欢迎",
            "route.dashboard": "仪表盘",
            "route.userInfo": "个人中心",
            "route.account": "账号管理",
            "route.fxshell": "FXShell 异常管理",
            "route.dataPermission": "数据权限",
            "route.auditLog": "审计日志",
            "route.customer": "客户管理",
            "route.order": "订单管理",
            "route.calcite": "数据查询（Calcite）",
            "route.langgraph": "LangGraph 线程",
            "route.chat": "智能对话",
            "route.license": "授权管理",
            "route.device": "设备管理",
            "route.plugin": "插件市场",
            "route.notFound": "页面不存在",
            "route.forbidden": "无权限访问",
            "route.wip": "页面开发中",
            // 框架
            "common.search": "搜索",
            "common.save": "保存",
            "common.cancel": "取消",
            "common.ok": "确定",
            "common.delete": "删除",
            "common.close": "关闭",
            "nav.openMenu": "打开菜单",
            "nav.profile": "个人中心",
            "nav.logout": "退出登录",
            "nav.closeOthers": "关闭其他标签",
            "ai.assistant": "EUM AI 助手",
            "nav.noMenus": "暂无菜单",
            "nav.noMenusHint": "登录后将从服务端同步菜单",
            // 设置页
            "config.title": "系统全局配置",
            "config.subtitle": "主题、AI 助手与多语言设置",
            "config.theme.title": "主题色调",
            "config.theme.subtitle": "选择即时预览，保存后全局生效",
            "config.theme.current": "当前值：",
            "config.theme.preset.black": "线框黑",
            "config.theme.preset.blue": "默认蓝",
            "config.theme.preset.brand": "品牌蓝",
            "config.theme.preset.green": "翡翠绿",
            "config.theme.preset.orange": "琥珀橙",
            "config.theme.preset.red": "珊瑚红",
            "config.theme.preset.indigo": "靛青紫",
            "config.ai.title": "AI 助手密钥",
            "config.ai.subtitle": "保存后 AI 助手按所选密钥对话",
            "config.ai.pick": "请选择",
            "config.ai.keyPrefix": "密钥",
            "config.ai.defaultModel": "默认模型",
            "config.ai.models": "已配 %d 个模型",
            "config.ai.noKeys": "尚未创建密钥：请先在「AI 配置」中新增供应商与密钥",
            "config.ai.noSelection": "未选择时由服务端使用默认密钥",
            "config.lang.title": "界面语言",
            "config.lang.subtitle": "保存后菜单、页签与接口语言立即切换",
            "config.lang.system": "跟随系统",
            "config.lang.switching": "正在切换语言…",
            "lang.zh-CN": "简体中文",
            "lang.en": "English",
            "lang.ja": "日本語",
            "config.adv.title": "多语言高级配置",
            "config.adv.visual": "可视化",
            "config.adv.json": "JSON",
            "config.adv.keyLabel": "翻译键",
            "config.adv.textLabel": "翻译文本",
            "config.adv.searchKey": "搜索翻译键",
            "config.adv.addWord": "添加词条",
            "config.adv.addLang": "添加语言",
            "config.adv.default": "默认",
            "config.empty.words": "暂无词条，点击「添加词条」开始",
            "config.empty.noMatch": "无匹配词条",
            "config.alert.addLang": "添加语言",
            "config.alert.langPlaceholder": "语言代码，如 en, zh-CN, ja",
            "config.alert.bcp47": "符合 BCP 47 标准的语言代码（例如: en, zh-CN, ja, zh-Hans-CN）",
            "config.alert.bcp47Error": "格式不符合 BCP 47 规范，注意大小写！",
            "config.toast.langSwitched": "语言已切换",
            "config.toast.saved": "配置已保存并生效",
            "config.toast.wordAdded": "已添加词条 %@",
            "config.toast.langAdded": "已添加语言 %@",
            "config.toast.jsonError": "JSON 格式不正确，无法保存！",
            "config.error.save": "保存失败",
            // 通用词汇（各界面机械替换使用）
            "button.resetPwd": "重置密码",
            "button.filter": "筛选",
            "common.loading": "加载中...",
            "common.noData": "暂无数据",
            "common.added": "新增成功",
            "common.updated": "修改成功",
            "common.deleted": "删除成功",
            "common.submitFailed": "提交失败",
            "common.opFailed": "操作失败",
            "common.loadFailed": "加载失败",
            "common.male": "男",
            "common.female": "女",
            "common.confirmDelete": "确认删除选中的 %d 项记录吗？",
            "common.confirmStatus": "确认%1$@%2$@吗？",
            "eum.placeholder.inputFormat": "请输入%1$@",
            "eum.placeholder.selectFormat": "请选择%1$@",
            "common.searchFormat": "搜索%1$@",
            "dict.data": "字典数据",
            "fxshell.markRepaired": "标记修复",
            "biz.markPaid": "标记已支付",
            "biz.markedPaid": "已标记为已支付",
            "dept.confirmDelete": "确认删除部门「%1$@」吗？",
            "dept.confirmStatus": "确认%1$@部门「%2$@」吗？",
            "menu.confirmDelete": "确认删除菜单「%1$@」吗？",
            "menu.confirmStatus": "确认%1$@菜单「%2$@」吗？",
            "user.confirmDelete": "确认删除 \"%1$@\" 吗？",
            "uralyt.confirmDeleteRecord": "确认删除该记录吗？",
            "license.confirmRevoke": "确定要吊销该授权单吗？此操作不可逆，将导致所有已绑定的设备失效！",
            "license.revokeBtn": "确定吊销",
            "license.revoked": "授权已吊销",
            "license.issued": "颁发授权成功！",
            "license.keyCopied": "授权密钥已复制到剪贴板",
            "device.unbindDone": "解除绑定成功",
            "device.rebindDone": "设备重新绑定成功",
            "device.bindDone": "绑定密钥成功",
            "device.applySubmitted": "申请已提交",
            "common.statusUpdated": "状态更新成功",
            "common.optional": "可选",
            "tab.detail": "详情 - %1$@",
            "tab.edit": "编辑 - %1$@",
            "dict.dataTitle": "字典数据 - %1$@",
            "ai.defaultModel": "默认模型",
            "plugin.iconUrl": "图标地址",
            "plugin.downloadUrl": "下载地址",
            "uralyt.avatar": "头像地址",
            "uralyt.morningDose": "早间剂量",
            "uralyt.noonDose": "午间剂量",
            "uralyt.eveningDose": "晚间剂量",
            "user.searchPlaceholder": "搜索用户名",
            "user.addTitle": "新增用户",
            "user.editTitle": "编辑用户",
            "user.password": "用户密码",
            "user.confirmPassword": "确认密码",
            "user.dept": "所属部门",
            "user.roles": "所属角色",
            "user.posts": "所属岗位",
            "user.noParent": "无上级部门",
            "user.newPassword": "新密码",
            "user.nameRequired": "用户名称不能为空",
            "user.nickRequired": "用户昵称不能为空",
            "user.pwdLength": "用户密码长度必须介于 5 和 20 之间",
            "user.pwdRule": "请输入 5~20 位新密码",
            "user.resetPwdFor": "重置密码 - %1$@",
            "user.batchPwdMessage": "这 %1$d 个用户的新密码",
            "user.statusChanged": "状态修改成功",
            "user.resetDone": "重置成功，新密码是：%1$@",
            "user.resetFailed": "重置失败",
            "user.batchResetDone": "批量修改成功，新密码是：%1$@",
            "dashboard.title": "仪表盘总览",
            "dashboard.subtitle": "欢迎回来，看看今天发生了什么。",
            "dashboard.stat.users": "总用户数",
            "dashboard.stat.visits": "今日访问",
            "dashboard.stat.orders": "总订单数",
            "dashboard.stat.revenue": "总营收",
            "dashboard.quickActions": "快捷操作",
            "dashboard.counter": "计数 +1（当前：%1$d）",
            "dashboard.addData": "添加数据",
            "dashboard.viewReports": "查看报表",
            "dashboard.systemSettings": "系统设置",
            "dashboard.mockAdd": "Mock：添加数据",
            "dashboard.mockReports": "Mock：查看报表",
            "welcome.title": "欢迎进入 EUM 核心系统",
            "welcome.goWorkspace": "进入工作台",
            "welcome.goLogin": "立即登录",
            "errors.notFoundDesc": "抱歉，您访问的页面不存在",
            "errors.forbiddenDesc": "抱歉，您没有权限访问此页面",
            "errors.backHome": "返回首页",
            "errors.wipDesc": "该功能正在火速建设中，敬请期待 🚀",
            "errors.backWelcome": "返回欢迎页",
            "errors.back": "返回上一页",
            "account.id": "账号 ID",
            "account.name": "账号名称",
            "ai.configuredModels": "已配模型",
            "ai.linkedKeys": "关联密钥",
            "ai.modelName": "模型名称",
            "audit.action": "操作类型",
            "audit.changeTime": "变更时间",
            "audit.changeType": "变更类型",
            "audit.ip": "IP 地址",
            "audit.newValue": "新值",
            "audit.oldToNew": "旧值 → 新值",
            "audit.oldValue": "旧值",
            "audit.result": "结果",
            "audit.time": "访问时间",
            "audit.user": "操作用户",
            "auth.deviceApply": "设备授权申请",
            "auth.login.withApple": "通过 Apple 登录",
            "auth.login.withGoogle": "通过 Google 登录",
            "auth.social.mock": "Mock：暂不支持第三方登录",
            "auth.social.mockRegister": "Mock：暂不支持第三方注册",
            "biz.amount": "订单金额",
            "biz.contactAddress": "联系地址",
            "biz.contactEmail": "联系邮箱",
            "biz.contactPerson": "联系人",
            "biz.contactPhone": "联系电话",
            "biz.customerCode": "客户编号",
            "biz.customerName": "客户名称",
            "biz.orderNo": "订单号",
            "biz.orderStatus": "订单状态",
            "biz.owner": "负责人",
            "calcite.run": "执行",
            "calcite.sqlEditable": "SQL（在下方编辑）",
            "chat.newSession": "新会话",
            "chat.send": "发送",
            "dept.parent": "上级部门",
            "device.deviceName": "设备名称",
            "device.lastActive": "最后活跃时间",
            "device.machineId": "机器特征码",
            "fxshell.errorLog": "错误日志",
            "fxshell.platform": "平台",
            "fxshell.recordNo": "记录编号",
            "fxshell.repaired": "已修复",
            "fxshell.unrepaired": "未修复",
            "langgraph.newThread": "新建线程",
            "langgraph.run": "运行",
            "langgraph.sessionBinding": "Session绑定",
            "langgraph.stream": "流式执行",
            "license.bindKey": "绑定密钥",
            "license.grantType": "授权类型",
            "license.id": "授权单ID",
            "license.issue": "颁发授权",
            "license.licenseKey": "授权密钥",
            "license.machineId": "机器码",
            "license.rebind": "重新绑定",
            "license.revoke": "吊销",
            "license.title": "授权单",
            "license.unbind": "解除绑定",
            "list.accounts": "账号列表",
            "list.customers": "客户列表",
            "list.depts": "部门列表",
            "list.dicts": "字典列表",
            "list.fxshell": "异常列表",
            "list.menus": "菜单列表",
            "list.orders": "订单列表",
            "list.posts": "岗位列表",
            "list.roles": "角色列表",
            "list.rules": "规则列表",
            "list.users": "用户列表",
            "perm.addRule": "新增规则",
            "perm.dataScope": "数据范围",
            "perm.exception": "例外",
            "perm.grant": "授权",
            "perm.grantType": "权限类型",
            "perm.resourceId": "资源ID",
            "perm.resourceType": "资源类型",
            "perm.ruleName": "规则名称",
            "perm.targetRole": "目标角色",
            "perm.targetUser": "目标用户",
            "plugin.add": "新增插件",
            "plugin.description": "描述",
            "plugin.id": "插件ID",
            "plugin.name": "插件名称",
            "plugin.needRestart": "需重启",
            "plugin.vendor": "开发商",
            "plugin.version": "版本",
            "tree.collapseAll": "折叠全部",
            "tree.expandAll": "展开全部",
            "uralyt.doctorNote": "医生备注",
            "uralyt.eveningPh": "晚间pH值",
            "uralyt.indicator": "化验指标",
            "uralyt.morningPh": "早间pH值",
            "uralyt.noonPh": "午间pH值",
            "uralyt.recordDate": "记录日期",
            "uralyt.status": "帐号状态",
            "uralyt.testDate": "化验日期",
            "uralyt.testType": "化验类型",
            "uralyt.userId": "关联用户ID",
            "uralyt.username": "用户账号",
            "user.userId": "用户ID",
        ],
        "en": [
            "route.welcome": "Welcome",
            "route.dashboard": "Dashboard",
            "route.userInfo": "Profile",
            "route.account": "Accounts",
            "route.fxshell": "FXShell Exceptions",
            "route.dataPermission": "Data Permissions",
            "route.auditLog": "Audit Log",
            "route.customer": "Customers",
            "route.order": "Orders",
            "route.calcite": "Data Query (Calcite)",
            "route.langgraph": "LangGraph Threads",
            "route.chat": "AI Chat",
            "route.license": "Licenses",
            "route.device": "Devices",
            "route.plugin": "Plugin Market",
            "route.notFound": "Page Not Found",
            "route.forbidden": "Access Denied",
            "route.wip": "Under Construction",
            "common.search": "Search",
            "common.save": "Save",
            "common.cancel": "Cancel",
            "common.ok": "OK",
            "common.delete": "Delete",
            "common.close": "Close",
            "nav.openMenu": "Open menu",
            "nav.profile": "Profile",
            "nav.logout": "Sign Out",
            "nav.closeOthers": "Close Other Tags",
            "ai.assistant": "EUM AI Assistant",
            "nav.noMenus": "No menus",
            "nav.noMenusHint": "Menus sync from the server after login",
            "config.title": "System Settings",
            "config.subtitle": "Theme, AI assistant & localization",
            "config.theme.title": "Theme Color",
            "config.theme.subtitle": "Preview instantly; applies globally after save",
            "config.theme.current": "Current: ",
            "config.theme.preset.black": "Wireframe Black",
            "config.theme.preset.blue": "Default Blue",
            "config.theme.preset.brand": "Brand Blue",
            "config.theme.preset.green": "Emerald",
            "config.theme.preset.orange": "Amber",
            "config.theme.preset.red": "Coral",
            "config.theme.preset.indigo": "Indigo",
            "config.ai.title": "AI Assistant Key",
            "config.ai.subtitle": "The assistant uses the selected key after save",
            "config.ai.pick": "Pick a key…",
            "config.ai.keyPrefix": "Key",
            "config.ai.defaultModel": "Default model",
            "config.ai.models": "%d model(s) configured",
            "config.ai.noKeys": "No keys yet — create a provider & key in AI Config first",
            "config.ai.noSelection": "Server default key is used when unset",
            "config.lang.title": "Interface Language",
            "config.lang.subtitle": "Menus, tags and API language switch right after save",
            "config.lang.system": "Follow System",
            "config.lang.switching": "Switching language…",
            "lang.zh-CN": "Simplified Chinese",
            "lang.en": "English",
            "lang.ja": "日本語",
            "config.adv.title": "Advanced Localization",
            "config.adv.visual": "Visual",
            "config.adv.json": "JSON",
            "config.adv.keyLabel": "Key",
            "config.adv.textLabel": "Text",
            "config.adv.searchKey": "Search keys",
            "config.adv.addWord": "Add Entry",
            "config.adv.addLang": "Add Language",
            "config.adv.default": "Default",
            "config.empty.words": "No entries yet — tap \"Add Entry\" to start",
            "config.empty.noMatch": "No matching entries",
            "config.alert.addLang": "Add Language",
            "config.alert.langPlaceholder": "Language code, e.g. en, zh-CN, ja",
            "config.alert.bcp47": "A valid BCP 47 tag (e.g. en, zh-CN, ja, zh-Hans-CN)",
            "config.alert.bcp47Error": "Invalid BCP 47 format — mind the casing!",
            "config.toast.langSwitched": "Language switched",
            "config.toast.saved": "Settings saved & applied",
            "config.toast.wordAdded": "Entry %@ added",
            "config.toast.langAdded": "Language %@ added",
            "config.toast.jsonError": "Invalid JSON — nothing saved!",
            "config.error.save": "Save failed",
            "button.resetPwd": "Reset Password",
            "button.filter": "Filter",
            "common.loading": "Loading...",
            "common.noData": "No data",
            "common.added": "Added",
            "common.updated": "Updated",
            "common.deleted": "Deleted",
            "common.submitFailed": "Submit failed",
            "common.opFailed": "Operation failed",
            "common.loadFailed": "Load failed",
            "common.male": "Male",
            "common.female": "Female",
            "common.confirmDelete": "Delete the selected %1$d item(s)?",
            "common.confirmStatus": "Confirm to %1$@%2$@?",
            "eum.placeholder.inputFormat": "Please input %1$@",
            "eum.placeholder.selectFormat": "Please select %1$@",
            "common.searchFormat": "Search %1$@",
            "dict.data": "Dict Data",
            "fxshell.markRepaired": "Mark Repaired",
            "biz.markPaid": "Mark Paid",
            "biz.markedPaid": "Marked as paid",
            "dept.confirmDelete": "Delete department \"%1$@\"?",
            "dept.confirmStatus": "Confirm to %1$@ department \"%2$@\"?",
            "menu.confirmDelete": "Delete menu \"%1$@\"?",
            "menu.confirmStatus": "Confirm to %1$@ menu \"%2$@\"?",
            "user.confirmDelete": "Delete \"%1$@\"?",
            "uralyt.confirmDeleteRecord": "Delete this record?",
            "license.confirmRevoke": "Revoke this license? This is irreversible and will invalidate all bound devices!",
            "license.revokeBtn": "Revoke",
            "license.revoked": "License revoked",
            "license.issued": "License issued!",
            "license.keyCopied": "License key copied to clipboard",
            "device.unbindDone": "Unbound",
            "device.rebindDone": "Device re-bound",
            "device.bindDone": "Key bound",
            "device.applySubmitted": "Application submitted",
            "common.statusUpdated": "Status updated",
            "common.optional": "Optional",
            "tab.detail": "Detail - %1$@",
            "tab.edit": "Edit - %1$@",
            "dict.dataTitle": "Dict Data - %1$@",
            "ai.defaultModel": "Default Model",
            "plugin.iconUrl": "Icon URL",
            "plugin.downloadUrl": "Download URL",
            "uralyt.avatar": "Avatar URL",
            "uralyt.morningDose": "Morning Dose",
            "uralyt.noonDose": "Noon Dose",
            "uralyt.eveningDose": "Evening Dose",
            "user.searchPlaceholder": "Search users",
            "user.addTitle": "Add User",
            "user.editTitle": "Edit User",
            "user.password": "Password",
            "user.confirmPassword": "Confirm Password",
            "user.dept": "Department",
            "user.roles": "Roles",
            "user.posts": "Posts",
            "user.noParent": "No parent",
            "user.newPassword": "New password",
            "user.nameRequired": "Username is required",
            "user.nickRequired": "Nickname is required",
            "user.pwdLength": "Password length must be between 5 and 20",
            "user.pwdRule": "Enter a 5-20 character new password",
            "user.resetPwdFor": "Reset password - %1$@",
            "user.batchPwdMessage": "New password for these %1$d users",
            "user.statusChanged": "Status updated",
            "user.resetDone": "Reset OK. New password: %1$@",
            "user.resetFailed": "Reset failed",
            "user.batchResetDone": "Batch reset OK. New password: %1$@",
            "dashboard.title": "Dashboard overview",
            "dashboard.subtitle": "Welcome back — here's what's happening today.",
            "dashboard.stat.users": "Total Users",
            "dashboard.stat.visits": "Today's Visits",
            "dashboard.stat.orders": "Total Orders",
            "dashboard.stat.revenue": "Total Revenue",
            "dashboard.quickActions": "Quick Actions",
            "dashboard.counter": "Counter +1 (Current: %1$d)",
            "dashboard.addData": "Add Data",
            "dashboard.viewReports": "View Reports",
            "dashboard.systemSettings": "System Settings",
            "dashboard.mockAdd": "Mock: Add Data",
            "dashboard.mockReports": "Mock: View Reports",
            "welcome.title": "Welcome to the EUM Core",
            "welcome.goWorkspace": "Enter Workspace",
            "welcome.goLogin": "Log In Now",
            "errors.notFoundDesc": "Sorry, the page you visited does not exist",
            "errors.forbiddenDesc": "Sorry, you do not have permission to access this page",
            "errors.backHome": "Back Home",
            "errors.wipDesc": "Under heavy construction — stay tuned 🚀",
            "errors.backWelcome": "Back to Welcome",
            "errors.back": "Back",
            "account.id": "Account ID",
            "account.name": "Account Name",
            "ai.configuredModels": "Configured Models",
            "ai.linkedKeys": "Linked Keys",
            "ai.modelName": "Model Name",
            "audit.action": "Action",
            "audit.changeTime": "Change Time",
            "audit.changeType": "Change Type",
            "audit.ip": "IP Address",
            "audit.newValue": "New Value",
            "audit.oldToNew": "Old → New",
            "audit.oldValue": "Old Value",
            "audit.result": "Result",
            "audit.time": "Access Time",
            "audit.user": "Operator",
            "auth.deviceApply": "Device Authorization",
            "auth.login.withApple": "Log in with Apple",
            "auth.login.withGoogle": "Log in with Google",
            "auth.social.mock": "Mock: third-party login not supported",
            "auth.social.mockRegister": "Mock: third-party sign-up not supported",
            "biz.amount": "Amount",
            "biz.contactAddress": "Address",
            "biz.contactEmail": "Contact Email",
            "biz.contactPerson": "Contact",
            "biz.contactPhone": "Contact Phone",
            "biz.customerCode": "Customer No.",
            "biz.customerName": "Customer Name",
            "biz.orderNo": "Order No.",
            "biz.orderStatus": "Order Status",
            "biz.owner": "Owner",
            "calcite.run": "Run",
            "calcite.sqlEditable": "SQL (edit below)",
            "chat.newSession": "New Chat",
            "chat.send": "Send",
            "dept.parent": "Parent Department",
            "device.deviceName": "Device Name",
            "device.lastActive": "Last Active",
            "device.machineId": "Machine ID",
            "fxshell.errorLog": "Error Log",
            "fxshell.platform": "Platform",
            "fxshell.recordNo": "Record No.",
            "fxshell.repaired": "Repaired",
            "fxshell.unrepaired": "Unrepaired",
            "langgraph.newThread": "New Thread",
            "langgraph.run": "Run",
            "langgraph.sessionBinding": "Session Binding",
            "langgraph.stream": "Stream",
            "license.bindKey": "Bind Key",
            "license.grantType": "Grant Type",
            "license.id": "License ID",
            "license.issue": "Issue License",
            "license.licenseKey": "License Key",
            "license.machineId": "Machine ID",
            "license.rebind": "Rebind",
            "license.revoke": "Revoke",
            "license.title": "License",
            "license.unbind": "Unbind",
            "list.accounts": "Accounts",
            "list.customers": "Customers",
            "list.depts": "Depts",
            "list.dicts": "Dicts",
            "list.fxshell": "Exceptions",
            "list.menus": "Menus",
            "list.orders": "Orders",
            "list.posts": "Posts",
            "list.roles": "Roles",
            "list.rules": "Rules",
            "list.users": "Users",
            "perm.addRule": "Add Rule",
            "perm.dataScope": "Data Scope",
            "perm.exception": "Exception",
            "perm.grant": "Grant",
            "perm.grantType": "Permission Type",
            "perm.resourceId": "Resource ID",
            "perm.resourceType": "Resource Type",
            "perm.ruleName": "Rule Name",
            "perm.targetRole": "Target Role",
            "perm.targetUser": "Target User",
            "plugin.add": "Add Plugin",
            "plugin.description": "Description",
            "plugin.id": "Plugin ID",
            "plugin.name": "Plugin Name",
            "plugin.needRestart": "Restart Required",
            "plugin.vendor": "Vendor",
            "plugin.version": "Version",
            "tree.collapseAll": "Collapse All",
            "tree.expandAll": "Expand All",
            "uralyt.doctorNote": "Doctor's Note",
            "uralyt.eveningPh": "Evening pH",
            "uralyt.indicator": "Indicator",
            "uralyt.morningPh": "Morning pH",
            "uralyt.noonPh": "Noon pH",
            "uralyt.recordDate": "Record Date",
            "uralyt.status": "Status",
            "uralyt.testDate": "Test Date",
            "uralyt.testType": "Test Type",
            "uralyt.userId": "Linked User ID",
            "uralyt.username": "Username",
            "user.userId": "User ID",
        ],
    ]
}
