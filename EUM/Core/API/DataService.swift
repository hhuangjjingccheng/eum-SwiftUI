import SwiftUI
import Combine

/// 数据服务层：对接后端 REST API（对齐 eum-front src/api/**）。
/// @Published 数组为“最近一次加载”的本地缓存，用于下拉选项 / 关联名称解析 / 树形展示。
@MainActor
final class DataService: ObservableObject {
    static let shared = DataService()

    let api = APIClient.shared

    // MARK: 本地缓存
    @Published var users: [SysUser] = []
    @Published var roles: [SysRole] = []
    @Published var posts: [SysPost] = []
    @Published var depts: [SysDept] = []
    @Published var menus: [SysMenu] = []
    @Published var dictTypes: [SysDictType] = []
    @Published var dictDatas: [SysDictData] = []
    @Published var providers: [AIProvider] = []
    @Published var apiKeys: [AIApiKey] = []
    @Published var apiKeyModels: [AIApiKeyModel] = []
    @Published var uralytUsers: [UralytUser] = []
    @Published var uricRecords: [UricRecord] = []
    @Published var medicalRecords: [MedicalRecord] = []
    @Published var devices: [Device] = []
    @Published var licenses: [License] = []
    @Published var plugins: [Plugin] = []
    @Published var sysConfig = SysConfig()

    init() {
        APIClient.shared.onUnauthorized = { [weak self] in
            Task { @MainActor in
                AppState.shared.handleUnauthorized()
                self?.clearCaches()
            }
        }
    }

    func clearCaches() {
        users = []; roles = []; posts = []; depts = []; menus = []
        dictTypes = []; dictDatas = []; providers = []; apiKeys = []; apiKeyModels = []
        uralytUsers = []; uricRecords = []; medicalRecords = []
        devices = []; licenses = []; plugins = []
    }

    /// 保留兼容（表单提交处调用；真实网络延迟由请求本身承担）
    func simulateNetwork() async throws {}

    /// 本地分页（对已缓存全量列表使用）
    static func paginate<T>(_ all: [T], page: Int, size: Int) -> PageResult<T> {
        let total = all.count
        let start = (page - 1) * size
        guard start < total else { return .init(content: [], total: total) }
        let end = min(start + size, total)
        return .init(content: Array(all[start..<end]), total: total)
    }

    /// 通用分页载荷（§2.2：pageNum 从 1 开始）
    func pageBody(page: Int, size: Int, extra: [String: Any] = [:]) -> [String: Any] {
        var body: [String: Any] = ["pageNum": page, "pageSize": size]
        for (k, v) in extra {
            if let s = v as? String, s.isEmpty { continue }
            body[k] = v
        }
        return body
    }

    // MARK: - 启动加载（登录后调用）

    /// 用户信息 + 菜单树 + 系统配置 + 基础字典
    func bootstrap() async throws {
        // 1. /auth/info
        let info = JV.dict(try await api.get("auth/info"))
        if !info.isEmpty {
            AppState.shared.currentUser = SysUser(dict: info)
            menus = JV.dictArray(info["eumRbacMenuList"]).map(SysMenu.init)
        }
        // 2. /sys/config/getConfig（多语言表 + 主题色；接口改动后统一收敛到 loadSysConfig）
        await loadSysConfig()
        // 3. 基础引用数据（并行拉取，失败不阻塞）
        async let rolesTask: () = loadRoles()
        async let postsTask: () = loadPosts()
        async let deptsTask: () = loadDeptTree()
        async let statusDictTask: () = loadStatusDict()
        _ = await (rolesTask, postsTask, deptsTask, statusDictTask)
    }

    func loadRoles() async {
        if let data = try? await api.post("eum_rbac_role/list"), let arr = data as? [Any] {
            roles = arr.compactMap { $0 as? [String: Any] }.map(SysRole.init)
        }
    }

    func loadPosts() async {
        if let data = try? await api.post("eum_rbac_post/list"), let arr = data as? [Any] {
            posts = arr.compactMap { $0 as? [String: Any] }.map(SysPost.init)
        }
    }

    func loadDeptTree() async {
        if let data = try? await api.post("eum_rbac_dept/treeList"), let arr = data as? [Any] {
            depts = arr.compactMap { $0 as? [String: Any] }.map(SysDept.init)
        }
    }

    func loadMenus() async {
        if let data = try? await api.post("eum_rbac_menu/treeList"), let arr = data as? [Any] {
            menus = arr.compactMap { $0 as? [String: Any] }.map(SysMenu.init)
        }
    }

    func loadStatusDict() async {
        guard let data = try? await api.post("system/dict/data/type/eum_status"),
              let arr = data as? [Any] else { return }
        let options = arr.compactMap { $0 as? [String: Any] }.map { d -> DictOption in
            DictOption(
                label: I18n.t(JV.string(d["i18nKey"]).isEmpty ? JV.string(d["dictLabel"]) : JV.string(d["i18nKey"])),
                value: JV.int(d["dictValue"]) ?? 0,
                kind: DictOption.kind(forListClass: JV.string(d["listClass"]))
            )
        }
        if !options.isEmpty { DictOption.eumStatus = options }
    }

    // MARK: - 关联名称解析（查缓存）

    func providerName(_ id: Int) -> String { providers.first { $0.id == id }?.providerName ?? "-" }
    func apiKeyDisplay(_ id: Int) -> String {
        guard let k = apiKeys.first(where: { $0.id == id }) else { return "-" }
        return "[\(providerName(k.providerId))] \(k.apiKeyPrefix)"
    }
    func deptName(_ id: Int?) -> String {
        guard let id, id != 0 else { return "无" }
        for d in depts { if let f = d.flattened().first(where: { $0.id == id }) { return f.deptName } }
        return "无"
    }
    func roleNames(_ ids: [Int]) -> String {
        let names = roles.filter { ids.contains($0.id) }.map(\.roleName)
        return names.isEmpty ? "无" : names.joined(separator: "，")
    }
    func postNames(_ ids: [Int]) -> String {
        let names = posts.filter { ids.contains($0.id) }.map(\.postName)
        return names.isEmpty ? "无" : names.joined(separator: "，")
    }

    // MARK: - 认证

    func login(username: String, password: String) async throws -> String {
        let data = try await api.post("auth/login", ["username": username, "password": password])
        guard let token = data as? String else {
            throw APIClient.ApiError(code: -1, message: "登录响应异常")
        }
        api.setToken(token)
        return token
    }

    func register(username: String, password: String) async throws {
        try await api.post("auth/register", ["username": username, "password": password])
    }

    func logout() async {
        try? await api.post("auth/logout")
        api.setToken(nil)
        clearCaches()
    }

    func updateProfile(_ user: SysUser, password: String?) async throws {
        var body: [String: Any] = [
            "eumRbacUserId": user.id,
            "username": user.username,
            "nickName": user.nickName,
            "realName": user.realName,
            "gender": user.gender,
            "status": user.status,
        ]
        // 脱敏剥离（对齐 web：包含 * 的手机号/邮箱不提交）
        if !user.phone.isEmpty && !user.phone.contains("*") { body["phone"] = user.phone }
        if !user.email.isEmpty && !user.email.contains("*") { body["email"] = user.email }
        if let password, !password.isEmpty { body["password"] = password }
        try await api.post("eum_rbac_user/update", body)
    }

    // MARK: - 系统用户

    func userPage(page: Int, size: Int, username: String, phone: String, status: Int?) async throws -> PageResult<SysUser> {
        var extra: [String: Any] = ["username": username, "phone": phone]
        if let status { extra["status"] = status }
        let data = try await api.post("eum_rbac_user/page", pageBody(page: page, size: size, extra: extra))
        return PageResult.parse(data, SysUser.init)
    }

    func userInsert(_ u: SysUser, password: String) async throws {
        var body: [String: Any] = [
            "username": u.username, "nickName": u.nickName, "realName": u.realName,
            "phone": u.phone, "email": u.email, "gender": u.gender, "status": u.status,
            "remark": u.remark, "password": password,
        ]
        if let d = u.deptId { body["eumRbacDeptId"] = d }
        body["eumRbacRoleIds"] = u.roleIds
        body["eumRbacPostIds"] = u.postIds
        try await api.post("eum_rbac_user/insert", body)
    }

    func userUpdate(_ u: SysUser) async throws {
        var body: [String: Any] = [
            "eumRbacUserId": u.id, "username": u.username, "nickName": u.nickName,
            "realName": u.realName, "gender": u.gender, "status": u.status, "remark": u.remark,
        ]
        if !u.phone.contains("*") { body["phone"] = u.phone }
        if !u.email.contains("*") { body["email"] = u.email }
        if let d = u.deptId { body["eumRbacDeptId"] = d }
        body["eumRbacRoleIds"] = u.roleIds
        body["eumRbacPostIds"] = u.postIds
        try await api.post("eum_rbac_user/update", body)
    }

    func userDelete(ids: [Int]) async throws {
        try await api.post("eum_rbac_user/delete", ["eumRbacUserIdList": ids])
    }

    func userStatus(id: Int, status: Int) async throws {
        try await api.post("eum_rbac_user/status", ["eumRbacUserId": id, "status": status])
    }

    func userResetPassword(ids: [Int], newPassword: String) async throws {
        try await api.post("eum_rbac_user/reset_password", ["eumRbacUserIdList": ids, "newPassword": newPassword])
    }

    // MARK: - 角色

    func rolePage(page: Int, size: Int, roleName: String, roleKey: String, status: Int?) async throws -> PageResult<SysRole> {
        var extra: [String: Any] = ["roleName": roleName, "roleKey": roleKey]
        if let status { extra["status"] = status }
        let data = try await api.post("eum_rbac_role/page", pageBody(page: page, size: size, extra: extra))
        return PageResult.parse(data, SysRole.init)
    }

    func roleDetail(id: Int) async throws -> SysRole {
        let data = try await api.post("eum_rbac_role/eumRbacRoleId", ["eumRbacRoleId": id])
        return SysRole(dict: JV.dict(data))
    }

    func roleInsert(_ r: SysRole) async throws {
        try await api.post("eum_rbac_role/insert", [
            "roleName": r.roleName, "roleKey": r.roleKey, "roleSort": r.roleSort,
            "status": r.status, "remark": r.remark, "eumRbacMenuIds": r.menuIds,
        ])
    }

    func roleUpdate(_ r: SysRole) async throws {
        try await api.post("eum_rbac_role/update", [
            "eumRbacRoleId": r.id, "roleName": r.roleName, "roleKey": r.roleKey,
            "roleSort": r.roleSort, "status": r.status, "remark": r.remark, "eumRbacMenuIds": r.menuIds,
        ])
    }

    func roleDelete(ids: [Int]) async throws {
        try await api.post("eum_rbac_role/delete", ["eumRbacRoleIdList": ids])
    }

    func roleStatus(id: Int, status: Int) async throws {
        try await api.post("eum_rbac_role/status", ["eumRbacRoleId": id, "status": status])
    }

    // MARK: - 岗位

    func postPage(page: Int, size: Int, postCode: String, postName: String, status: Int?) async throws -> PageResult<SysPost> {
        var extra: [String: Any] = ["postCode": postCode, "postName": postName]
        if let status { extra["status"] = status }
        let data = try await api.post("eum_rbac_post/page", pageBody(page: page, size: size, extra: extra))
        return PageResult.parse(data, SysPost.init)
    }

    func postInsert(_ p: SysPost) async throws {
        try await api.post("eum_rbac_post/insert", [
            "postName": p.postName, "postCode": p.postCode, "postSort": p.postSort,
            "status": p.status, "remark": p.remark,
        ])
    }

    func postUpdate(_ p: SysPost) async throws {
        try await api.post("eum_rbac_post/update", [
            "eumRbacPostId": p.id, "postName": p.postName, "postCode": p.postCode,
            "postSort": p.postSort, "status": p.status, "remark": p.remark,
        ])
    }

    func postDelete(ids: [Int]) async throws {
        try await api.post("eum_rbac_post/delete", ["eumRbacPostIdList": ids])
    }

    func postStatus(id: Int, status: Int) async throws {
        try await api.post("eum_rbac_post/status", ["eumRbacPostId": id, "status": status])
    }

    // MARK: - 部门

    func deptInsert(_ d: SysDept) async throws {
        var body: [String: Any] = [
            "parentId": d.parentId, "deptName": d.deptName, "orderNum": d.orderNum,
            "leader": d.leader, "phone": d.phone, "email": d.email, "status": d.status,
        ]
        if let anc = depts.first(where: { $0.id == d.parentId })?.ancestors {
            body["ancestors"] = anc.isEmpty ? "0" : anc + ",\(d.parentId)"
        }
        try await api.post("eum_rbac_dept/insert", body)
    }

    func deptUpdate(_ d: SysDept) async throws {
        try await api.post("eum_rbac_dept/update", [
            "eumRbacDeptId": d.id, "parentId": d.parentId, "deptName": d.deptName,
            "orderNum": d.orderNum, "leader": d.leader, "phone": d.phone,
            "email": d.email, "status": d.status,
        ])
    }

    // MARK: - 菜单

    func menuInsert(_ m: SysMenu) async throws {
        try await api.post("eum_rbac_menu/insert", menuPayload(m, withId: false))
    }

    func menuUpdate(_ m: SysMenu) async throws {
        try await api.post("eum_rbac_menu/update", menuPayload(m, withId: true))
    }

    private func menuPayload(_ m: SysMenu, withId: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "parentId": m.parentId, "menuName": m.menuName, "path": m.path,
            "component": m.component, "routeName": m.routeName, "icon": m.icon,
            "menuType": m.menuType, "orderNum": m.orderNum, "isFrame": m.isFrame,
            "isCache": m.isCache, "visible": m.visible, "status": m.status,
            "perms": m.perms, "remark": m.remark,
        ]
        if withId { body["eumRbacMenuId"] = m.id }
        return body
    }

    // MARK: - 字典

    func dictTypePage(page: Int, size: Int, dictName: String, dictType: String, status: Int?) async throws -> PageResult<SysDictType> {
        var extra: [String: Any] = ["dictName": dictName, "dictType": dictType]
        if let status { extra["status"] = status }
        let data = try await api.post("system/dict/type/page", pageBody(page: page, size: size, extra: extra))
        return PageResult.parse(data, SysDictType.init)
    }

    func dictTypeInsert(_ t: SysDictType) async throws {
        try await api.post("system/dict/type/insert", [
            "dictName": t.dictName, "dictType": t.dictType, "status": t.status, "remark": t.remark,
        ])
    }

    func dictTypeUpdate(_ t: SysDictType) async throws {
        try await api.post("system/dict/type/update", [
            "eumDictionaryTypeId": t.id, "dictName": t.dictName, "dictType": t.dictType,
            "status": t.status, "remark": t.remark,
        ])
    }

    func dictTypeDelete(ids: [Int]) async throws {
        try await api.post("system/dict/type/delete", ["eumDictionaryTypeIdList": ids])
    }

    func dictDataPage(page: Int, size: Int, typeId: Int, dictLabel: String) async throws -> PageResult<SysDictData> {
        let data = try await api.post("system/dict/data/page", pageBody(page: page, size: size, extra: [
            "eumDictionaryTypeId": typeId, "dictLabel": dictLabel,
        ]))
        return PageResult.parse(data, SysDictData.init)
    }

    func dictDataInsert(_ d: SysDictData) async throws {
        try await api.post("system/dict/data/insert", [
            "eumDictionaryTypeId": d.typeId, "dictLabel": d.dictLabel, "dictValue": d.dictValue,
            "i18nKey": d.i18nKey, "dictSort": d.dictSort, "status": d.status,
            "cssClass": d.cssClass, "listClass": d.listClass, "remark": d.remark,
        ])
    }

    func dictDataUpdate(_ d: SysDictData) async throws {
        try await api.post("system/dict/data/update", [
            "eumDictionaryDataId": d.id, "eumDictionaryTypeId": d.typeId, "dictLabel": d.dictLabel,
            "dictValue": d.dictValue, "i18nKey": d.i18nKey, "dictSort": d.dictSort,
            "status": d.status, "cssClass": d.cssClass, "listClass": d.listClass, "remark": d.remark,
        ])
    }

    func dictDataDelete(ids: [Int]) async throws {
        try await api.post("system/dict/data/delete", ["eumDictionaryDataIdList": ids])
    }

    // MARK: - 系统配置

    /// GET /sys/config/getConfig（免认证：登录 / 注册页启动时即可取到配置；
    /// 未认证时服务端不返回 eumEumAiApiKey）
    func loadSysConfig() async {
        if let data = try? await api.get("sys/config/getConfig"), let d = data as? [String: Any] {
            var c = SysConfig()
            c.configId = JV.int(d["eumConfigId"]) ?? 0
            c.themeColor = JV.string(d["themeColor"])
            c.assistantApiKeyId = JV.int(d["eumEumAiApiKey"])
            c.language = JV.string(d["language"]).isEmpty ? "zh-CN" : JV.string(d["language"])
            c.languageJson = d["languageJson"] as? [String: Any] ?? [:]
            sysConfig = c
            Theme.applyThemeColor(c.themeColor)
            I18n.apply(languageJson: c.languageJson, language: c.language)
            APIClient.shared.language = I18n.language
            // 词条 / 主题变化驱动全局重建（登录 / 注册页观察 app 即可刷新）
            AppState.shared.i18nVersion += 1
        }
    }

    func saveSysConfig(_ c: SysConfig) async throws {
        // PUT /sys/config/updateConfig（EumConfigUpdateDTO 无 eumConfigId 字段；
        // 服务端 MapStruct 对 null 忽略更新，故未设置的项不要传，避免误覆盖）
        var body: [String: Any] = [
            "themeColor": c.themeColor,
            "language": c.language,
            "languageJson": c.languageJson,
        ]
        if let apiKeyId = c.assistantApiKeyId {
            body["eumEumAiApiKey"] = apiKeyId
        }
        try await api.put("sys/config/updateConfig", body)
    }

    // MARK: - AI 配置

    func providerPage(page: Int, size: Int, providerName: String, status: Int?) async throws -> PageResult<AIProvider> {
        var extra: [String: Any] = ["providerName": providerName]
        if let status { extra["status"] = status }
        let data = try await api.post("eum_ai_provider/page", pageBody(page: page, size: size, extra: extra))
        return PageResult.parse(data, AIProvider.init)
    }

    func providerInsert(_ p: AIProvider) async throws {
        try await api.post("eum_ai_provider/insert", [
            "providerName": p.providerName, "providerCode": p.providerCode,
            "baseUrl": p.baseUrl, "status": p.status, "remark": p.remark,
        ])
    }

    func providerUpdate(_ p: AIProvider) async throws {
        try await api.post("eum_ai_provider/update", [
            "eumAiProviderId": p.id, "providerName": p.providerName, "providerCode": p.providerCode,
            "baseUrl": p.baseUrl, "status": p.status, "remark": p.remark,
        ])
    }

    func providerDelete(ids: [Int]) async throws {
        try await api.post("eum_ai_provider/delete", ["eumAiProviderIds": ids])
    }

    func loadProviders() async {
        if let data = try? await api.post("eum_ai_provider/page", ["pageNum": 1, "pageSize": 1000]) {
            providers = PageResult.parse(data, AIProvider.init).content
        }
    }

    func loadApiKeys() async {
        if let data = try? await api.post("eum_ai_api_key/page", ["pageNum": 1, "pageSize": 1000]) {
            apiKeys = PageResult.parse(data, AIApiKey.init).content
        }
    }

    func apiKeyInsert(_ k: AIApiKey) async throws {
        try await api.post("eum_ai_api_key/insert", [
            "eumAiProviderId": k.providerId, "apiKey": k.apiKey, "status": k.status, "remark": k.remark,
        ])
    }

    func apiKeyUpdate(_ k: AIApiKey) async throws {
        try await api.post("eum_ai_api_key/update", [
            "eumAiApiKeyId": k.id, "eumAiProviderId": k.providerId, "apiKey": k.apiKey,
            "status": k.status, "remark": k.remark,
        ])
    }

    func apiKeyDelete(ids: [Int]) async throws {
        try await api.post("eum_ai_api_key/delete", ["eumAiApiKeyIds": ids])
    }

    func apiKeyStatus(id: Int, status: Int) async throws {
        try await api.post("eum_ai_api_key/status", ["eumAiApiKeyId": id, "status": status])
    }

    func apiKeyDetail(id: Int) async throws -> AIApiKey {
        let data = try await api.post("eum_ai_api_key/eumAiApiKeyId", ["eumAiApiKeyId": id])
        return AIApiKey(dict: JV.dict(data))
    }

    func apiKeyModelPage(page: Int, size: Int, apiKeyId: Int?) async throws -> PageResult<AIApiKeyModel> {
        var extra: [String: Any] = [:]
        if let apiKeyId { extra["eumAiApiKeyId"] = apiKeyId }
        let data = try await api.post("eum_ai_api_key_model/page", pageBody(page: page, size: size, extra: extra))
        return PageResult.parse(data, AIApiKeyModel.init)
    }

    func apiKeyModelInsert(_ m: AIApiKeyModel) async throws {
        try await api.post("eum_ai_api_key_model/insert", [
            "eumAiApiKeyId": m.apiKeyId, "model": m.model, "status": m.status, "remark": m.remark,
        ])
    }

    func apiKeyModelUpdate(_ m: AIApiKeyModel) async throws {
        try await api.post("eum_ai_api_key_model/update", [
            "eumAiApiKeyModelId": m.id, "eumAiApiKeyId": m.apiKeyId, "model": m.model,
            "status": m.status, "remark": m.remark,
        ])
    }

    func apiKeyModelDelete(ids: [Int]) async throws {
        try await api.post("eum_ai_api_key_model/delete", ["eumAiApiKeyModelIds": ids])
    }

    func apiKeyModelStatus(id: Int, status: Int) async throws {
        try await api.post("eum_ai_api_key_model/status", ["eumAiApiKeyModelId": id, "status": status])
    }

    // MARK: - 友来特

    func uralytUserPage(page: Int, size: Int) async throws -> PageResult<UralytUser> {
        let data = try await api.post("uralyt_user/page", pageBody(page: page, size: size))
        return PageResult.parse(data, UralytUser.init)
    }

    func uralytUserInsert(_ u: UralytUser) async throws {
        try await api.post("uralyt_user/insert", [
            "username": u.username, "phone": u.phone, "password": u.password,
            "nickname": u.nickname, "gender": u.gender, "status": u.status, "avatar": u.avatar,
        ])
    }

    func uralytUserUpdate(_ u: UralytUser) async throws {
        try await api.post("uralyt_user/update", [
            "uralytUserId": u.id, "username": u.username, "phone": u.phone,
            "nickname": u.nickname, "gender": u.gender, "status": u.status, "avatar": u.avatar,
        ])
    }

    func uralytUserDelete(ids: [Int]) async throws {
        try await api.post("uralyt_user/delete", ["ids": ids])
    }

    func uricPage(page: Int, size: Int) async throws -> PageResult<UricRecord> {
        let data = try await api.post("uralyt_ph_record/page", pageBody(page: page, size: size))
        return PageResult.parse(data, UricRecord.init)
    }

    func uricInsert(_ r: UricRecord) async throws {
        try await api.post("uralyt_ph_record/insert", uricPayload(r, withId: false))
    }

    func uricUpdate(_ r: UricRecord) async throws {
        try await api.post("uralyt_ph_record/update", uricPayload(r, withId: true))
    }

    private func uricPayload(_ r: UricRecord, withId: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "uralytUserId": r.userId, "recordDate": r.recordDate,
            "morningPh": JV.double(r.morningPh) ?? 0,
            "noonPh": JV.double(r.noonPh) ?? 0,
            "eveningPh": JV.double(r.eveningPh) ?? 0,
            "morningDosage": JV.double(r.morningDosage) ?? 0,
            "noonDosage": JV.double(r.noonDosage) ?? 0,
            "eveningDosage": JV.double(r.eveningDosage) ?? 0,
            "notes": r.notes,
        ]
        if withId { body["uralytPhRecordId"] = r.id }
        return body
    }

    func uricDelete(ids: [Int]) async throws {
        try await api.post("uralyt_ph_record/delete", ["ids": ids])
    }

    func medicalPage(page: Int, size: Int) async throws -> PageResult<MedicalRecord> {
        let data = try await api.post("uralyt_medical_record/page", pageBody(page: page, size: size))
        return PageResult.parse(data, MedicalRecord.init)
    }

    func medicalInsert(_ r: MedicalRecord) async throws {
        try await api.post("uralyt_medical_record/insert", medicalPayload(r, withId: false))
    }

    func medicalUpdate(_ r: MedicalRecord) async throws {
        try await api.post("uralyt_medical_record/update", medicalPayload(r, withId: true))
    }

    private func medicalPayload(_ r: MedicalRecord, withId: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "uralytUserId": r.userId, "recordDate": r.recordDate, "recordType": r.recordType,
            "indicators": r.indicators, "doctorNotes": r.doctorNotes,
        ]
        if withId { body["uralytMedicalRecordId"] = r.id }
        return body
    }

    func medicalDelete(ids: [Int]) async throws {
        try await api.post("uralyt_medical_record/delete", ["ids": ids])
    }

    // MARK: - 应用管理（授权 / 设备 / 插件）

    func licensePage(page: Int, size: Int, machineId: String, licenseKey: String) async throws -> PageResult<License> {
        let data = try await api.post("licenses/page", pageBody(page: page, size: size, extra: [
            "machineId": machineId, "licenseKey": licenseKey,
        ]))
        return PageResult.parse(data, License.init)
    }

    func licenseIssue(userId: Int?, licenseType: String, maxDevices: Int, validDays: Int, remark: String) async throws {
        var body: [String: Any] = [
            "licenseType": licenseType, "maxDevices": maxDevices, "validDays": validDays, "remark": remark,
        ]
        if let userId { body["userId"] = userId }
        try await api.post("licenses/issue", body)
    }

    func licenseRevoke(id: Int) async throws {
        try await api.post("licenses/\(id)/revoke")
    }

    func devices(of license: License) async -> [Device] {
        if let data = try? await api.get("licenses/machines/list", query: ["licenseId": "\(license.id)"]),
           let arr = data as? [Any] {
            return arr.compactMap { $0 as? [String: Any] }.map(Device.init)
        }
        return []
    }

    func devicePage(page: Int, size: Int, machineId: String, deviceName: String, email: String) async throws -> PageResult<Device> {
        let data = try await api.post("licenses/machines/page", pageBody(page: page, size: size, extra: [
            "machineId": machineId, "deviceName": deviceName, "email": email,
        ]))
        return PageResult.parse(data, Device.init)
    }

    func deviceUnbind(id: Int) async throws {
        try await api.delete("licenses/machines/\(id)")
    }

    func deviceRebind(id: Int) async throws {
        try await api.post("licenses/machines/\(id)/bind")
    }

    func deviceBindKey(id: Int, licenseKey: String) async throws {
        try await api.post("licenses/machines/\(id)/bind-key", ["licenseKey": licenseKey])
    }

    func deviceApply(machineId: String, email: String) async throws {
        try await api.post("licenses/machines/apply", ["machineId": machineId, "email": email])
    }

    func loadPlugins() async {
        if let data = try? await api.get("plugins/market/list"), let arr = data as? [Any] {
            plugins = arr.compactMap { $0 as? [String: Any] }.map(Plugin.init)
        }
    }

    func pluginSave(_ p: Plugin) async throws {
        try await api.post("plugins/market/save", p.payload)
    }

    // MARK: - Chat

    struct ChatModelInfo {
        let defaultModel: String
        let models: [AIModel]
    }

    func chatModels() async throws -> ChatModelInfo {
        let data = try await api.get("chat/models")
        let d = JV.dict(data)
        return ChatModelInfo(
            defaultModel: JV.string(d["defaultModel"]),
            models: JV.dictArray(d["models"]).map(AIModel.init)
        )
    }
}
