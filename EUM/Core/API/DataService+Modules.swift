import Foundation

/// 数据服务层扩展：补齐 `eum/doc/api-endpoints.json` 中尚未对接的端点。
/// 字段命名严格对齐 `API对接文档.md` 各 DTO。
extension DataService {

    // MARK: - 用户缓存辅助（下拉选项 / 名称解析）

    /// 加载一批系统用户用于下拉选项（负责人、创建人等）
    func loadUsers(pageSize: Int = 200) async {
        if let data = try? await api.post("eum_rbac_user/page", pageBody(page: 1, size: pageSize)),
           let result = data as? [String: Any] {
            users = PageResult.parse(result, SysUser.init).content
        }
    }

    /// 可选人员：当前登录用户 + 已缓存的系统用户（去重）
    var allUsers: [SysUser] {
        var list = users
        let me = AppState.shared.currentUser
        if me.id != 0, !list.contains(where: { $0.id == me.id }) { list.insert(me, at: 0) }
        return list
    }

    /// 按用户ID取展示名（未命中回退 ID 或 "-")
    func userName(_ id: Int?) -> String {
        guard let id, id != 0 else { return "-" }
        if let u = users.first(where: { $0.id == id }) { return u.displayLabel }
        let me = AppState.shared.currentUser
        if me.id == id { return me.displayLabel }
        return "用户 #\(id)"
    }

    // MARK: - 认证补充

    /// §4.4.2 手机号 + 验证码登录
    func loginWithPhone(phone: String, code: String) async throws -> String {
        let data = try await api.post("auth/login/phone", ["phone": phone, "code": code])
        guard let token = data as? String else {
            throw APIClient.ApiError(code: -1, message: "登录响应异常")
        }
        api.setToken(token)
        return token
    }

    /// §4.4.3 主动续期会话（401 时由 APIClient 自动调用，此处供手动刷新）
    @discardableResult
    func refreshSession() async throws -> String {
        let token = try await api.refreshToken()
        api.setToken(token)
        return token
    }

    // MARK: - 部门（eum_rbac_dept 补全）

    func deptPage(page: Int, size: Int, deptName: String, status: Int?) async throws -> PageResult<SysDept> {
        var extra: [String: Any] = ["deptName": deptName]
        if let status { extra["status"] = status }
        let data = try await api.post("eum_rbac_dept/page", pageBody(page: page, size: size, extra: extra))
        return PageResult.parse(data, SysDept.init)
    }

    func deptDetail(id: Int) async throws -> SysDept {
        let data = try await api.post("eum_rbac_dept/eumRbacDeptId", ["eumRbacDeptId": id])
        return SysDept(dict: JV.dict(data))
    }

    func deptDelete(ids: [Int]) async throws {
        try await api.post("eum_rbac_dept/delete", ["eumRbacDeptIdList": ids])
    }

    func deptStatus(id: Int, status: Int) async throws {
        try await api.post("eum_rbac_dept/status", ["eumRbacDeptId": id, "status": status])
    }

    // MARK: - 菜单（eum_rbac_menu 补全）

    func menuPage(page: Int, size: Int, menuName: String, status: Int?) async throws -> PageResult<SysMenu> {
        var extra: [String: Any] = ["menuName": menuName]
        if let status { extra["status"] = status }
        let data = try await api.post("eum_rbac_menu/page", pageBody(page: page, size: size, extra: extra))
        return PageResult.parse(data, SysMenu.init)
    }

    func menuDetail(id: Int) async throws -> SysMenu {
        let data = try await api.post("eum_rbac_menu/eumRbacMenuId", ["eumRbacMenuId": id])
        return SysMenu(dict: JV.dict(data))
    }

    func menuDelete(ids: [Int]) async throws {
        try await api.post("eum_rbac_menu/delete", ["eumRbacMenuIdList": ids])
    }

    func menuStatus(id: Int, status: Int) async throws {
        try await api.post("eum_rbac_menu/status", ["eumRbacMenuId": id, "status": status])
    }

    // MARK: - 岗位 / 用户 / 字典 补全

    func postDetail(id: Int) async throws -> SysPost {
        let data = try await api.post("eum_rbac_post/eumRbacPostId", ["eumRbacPostId": id])
        return SysPost(dict: JV.dict(data))
    }

    /// §4.23 根据用户ID查询用户（含角色 / 岗位关联，用于编辑表单回填）
    func userDetail(id: Int) async throws -> SysUser {
        let data = try await api.post("eum_rbac_user/eumRbacUserId", ["eumRbacUserId": id])
        return SysUser(dict: JV.dict(data))
    }

    /// §4.23 单用户重置密码（PasswordDTO）
    func userResetPassword(id: Int, oldPassword: String?, newPassword: String) async throws {
        var body: [String: Any] = ["eumRbacUserId": id, "newPassword": newPassword]
        if let oldPassword, !oldPassword.isEmpty { body["oldPassword"] = oldPassword }
        try await api.post("eum_rbac_user/password", body)
    }

    func dictTypeDetail(id: Int) async throws -> SysDictType {
        let data = try await api.post("system/dict/type/detail", ["eumDictionaryTypeId": id])
        return SysDictType(dict: JV.dict(data))
    }

    func dictDataDetail(id: Int) async throws -> SysDictData {
        let data = try await api.post("system/dict/data/detail", ["eumDictionaryDataId": id])
        return SysDictData(dict: JV.dict(data))
    }

    /// §4.31 按字典类型取字典数据（下拉 / 状态标签基础数据）
    func dictData(byType type: String) async -> [SysDictData] {
        guard let data = try? await api.post("system/dict/data/type/\(type)"),
              let arr = data as? [Any] else { return [] }
        return arr.compactMap { $0 as? [String: Any] }.map(SysDictData.init)
    }

    // MARK: - AI 配置补全

    func providerDetail(id: Int) async throws -> AIProvider {
        let data = try await api.post("eum_ai_provider/eumAiProviderId", ["eumAiProviderId": id])
        return AIProvider(dict: JV.dict(data))
    }

    func loadAllProviders() async {
        if let data = try? await api.post("eum_ai_provider/list"), let arr = data as? [Any] {
            providers = arr.compactMap { $0 as? [String: Any] }.map(AIProvider.init)
        }
    }

    func loadAllApiKeys() async {
        if let data = try? await api.post("eum_ai_api_key/list"), let arr = data as? [Any] {
            apiKeys = arr.compactMap { $0 as? [String: Any] }.map(AIApiKey.init)
        }
    }

    func apiKeyModelDetail(id: Int) async throws -> AIApiKeyModel {
        let data = try await api.post("eum_ai_api_key_model/eumAiApiKeyModelId", ["eumAiApiKeyModelId": id])
        return AIApiKeyModel(dict: JV.dict(data))
    }

    func loadAllApiKeyModels() async {
        if let data = try? await api.post("eum_ai_api_key_model/list"), let arr = data as? [Any] {
            apiKeyModels = arr.compactMap { $0 as? [String: Any] }.map(AIApiKeyModel.init)
        }
    }

    // MARK: - 友来特补全

    func uralytUserGet(id: Int) async throws -> UralytUser {
        let data = try await api.post("uralyt_user/getById", ["uralytUserId": id])
        return UralytUser(dict: JV.dict(data))
    }

    func uricGet(id: Int) async throws -> UricRecord {
        let data = try await api.post("uralyt_ph_record/getById", ["uralytPhRecordId": id])
        return UricRecord(dict: JV.dict(data))
    }

    func medicalGet(id: Int) async throws -> MedicalRecord {
        let data = try await api.post("uralyt_medical_record/getById", ["uralytMedicalRecordId": id])
        return MedicalRecord(dict: JV.dict(data))
    }

    // MARK: - FXShell 异常管理（bovinishell）

    func fxshellPage(page: Int, size: Int, platform: String, isRepair: String, email: String) async throws -> PageResult<FxshellLog> {
        let data = try await api.post("bovinishell/page", pageBody(page: page, size: size, extra: [
            "platform": platform, "isRepair": isRepair, "email": email,
        ]))
        return PageResult.parse(data, FxshellLog.init)
    }

    func fxshellListAll() async -> [FxshellLog] {
        guard let data = try? await api.post("bovinishell/list"), let arr = data as? [Any] else { return [] }
        return arr.compactMap { $0 as? [String: Any] }.map(FxshellLog.init)
    }

    func fxshellDetail(id: Int) async throws -> FxshellLog {
        let data = try await api.post("bovinishell/eumFxshellId", ["eumFxshellId": id])
        return FxshellLog(dict: JV.dict(data))
    }

    func fxshellInsert(_ log: FxshellLog) async throws {
        try await api.post("bovinishell/insert", fxshellPayload(log, withId: false))
    }

    func fxshellUpdate(_ log: FxshellLog) async throws {
        try await api.post("bovinishell/update", fxshellPayload(log, withId: true))
    }

    private func fxshellPayload(_ log: FxshellLog, withId: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "errorLog": log.errorLog, "platform": log.platform,
            "isRepair": log.isRepair, "email": log.email,
        ]
        if withId { body["eumFxshellId"] = log.id }
        return body
    }

    func fxshellDelete(ids: [Int]) async throws {
        try await api.post("bovinishell/delete", ["eumFxshellIds": ids])
    }

    // MARK: - 客户管理（biz_customer）

    func customerPage(page: Int, size: Int, customerName: String, contactPhone: String, status: Int?) async throws -> PageResult<BizCustomer> {
        var extra: [String: Any] = ["customerName": customerName, "contactPhone": contactPhone]
        if let status { extra["status"] = status }
        let data = try await api.post("biz_customer/page", pageBody(page: page, size: size, extra: extra))
        return PageResult.parse(data, BizCustomer.init)
    }

    func customerDetail(id: Int) async throws -> BizCustomer {
        let data = try await api.post("biz_customer/customerId", ["customerId": id])
        return BizCustomer(dict: JV.dict(data))
    }

    func customerInsert(_ c: BizCustomer) async throws {
        try await api.post("biz_customer/insert", customerPayload(c, withId: false))
    }

    func customerUpdate(_ c: BizCustomer) async throws {
        try await api.post("biz_customer/update", customerPayload(c, withId: true))
    }

    private func customerPayload(_ c: BizCustomer, withId: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "customerName": c.customerName, "contactPerson": c.contactPerson,
            "contactPhone": c.contactPhone, "contactEmail": c.contactEmail,
            "address": c.address, "status": c.status, "remark": c.remark,
        ]
        if let owner = c.ownerId { body["ownerId"] = owner }
        if let dept = c.deptId { body["eumRbacDeptId"] = dept }
        if withId { body["customerId"] = c.id }
        return body
    }

    func customerDelete(ids: [Int]) async throws {
        try await api.post("biz_customer/delete", ["customerIdList": ids])
    }

    func customerStatus(id: Int, status: Int) async throws {
        try await api.post("biz_customer/status", ["customerId": id, "status": status])
    }

    // MARK: - 订单管理（biz_order）

    func orderPage(page: Int, size: Int, orderNo: String, customerId: Int?, status: Int?) async throws -> PageResult<BizOrder> {
        var extra: [String: Any] = ["orderNo": orderNo]
        if let customerId { extra["customerId"] = customerId }
        if let status { extra["status"] = status }
        let data = try await api.post("biz_order/page", pageBody(page: page, size: size, extra: extra))
        return PageResult.parse(data, BizOrder.init)
    }

    func orderDetail(id: Int) async throws -> BizOrder {
        let data = try await api.post("biz_order/orderId", ["orderId": id])
        return BizOrder(dict: JV.dict(data))
    }

    func orderInsert(_ o: BizOrder) async throws {
        try await api.post("biz_order/insert", orderPayload(o, withId: false))
    }

    func orderUpdate(_ o: BizOrder) async throws {
        try await api.post("biz_order/update", orderPayload(o, withId: true))
    }

    private func orderPayload(_ o: BizOrder, withId: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "orderNo": o.orderNo, "customerName": o.customerName,
            "amount": JV.double(o.amount) ?? 0, "status": o.status, "remark": o.remark,
        ]
        if let cid = o.customerId { body["customerId"] = cid }
        if let creator = o.creatorId { body["creatorId"] = creator }
        if let dept = o.deptId { body["eumRbacDeptId"] = dept }
        if withId { body["orderId"] = o.id }
        return body
    }

    func orderDelete(ids: [Int]) async throws {
        try await api.post("biz_order/delete", ["orderIdList": ids])
    }

    func orderStatus(id: Int, status: Int) async throws {
        try await api.post("biz_order/status", ["orderId": id, "status": status])
    }

    // MARK: - 数据权限规则（eum_data_permission_rule）

    func permissionRuleList(resourceType: String) async -> [PermissionRule] {
        guard let data = try? await api.post("eum_data_permission_rule/listByResourceType", ["resourceType": resourceType]),
              let arr = data as? [Any] else { return [] }
        return arr.compactMap { $0 as? [String: Any] }.map(PermissionRule.init)
    }

    func permissionRuleDetail(id: Int) async throws -> PermissionRule {
        let data = try await api.post("eum_data_permission_rule/getById", ["ruleId": id])
        return PermissionRule(dict: JV.dict(data))
    }

    func permissionRuleInsert(_ r: PermissionRule) async throws {
        try await api.post("eum_data_permission_rule/insert", permissionRulePayload(r, withId: false))
    }

    func permissionRuleUpdate(_ r: PermissionRule) async throws {
        try await api.post("eum_data_permission_rule/update", permissionRulePayload(r, withId: true))
    }

    private func permissionRulePayload(_ r: PermissionRule, withId: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "ruleName": r.ruleName, "resourceType": r.resourceType,
            "permissionType": r.permissionType, "dataScope": r.dataScope,
            "status": r.status, "remark": r.remark,
        ]
        if withId { body["ruleId"] = r.id }
        return body
    }

    func permissionRuleDelete(ids: [Int]) async throws {
        try await api.post("eum_data_permission_rule/delete", ["ruleIdList": ids])
    }

    // MARK: - 数据权限授权（eum_data_permission_grant）

    func permissionGrantList(ruleId: Int) async -> [PermissionGrant] {
        guard let data = try? await api.post("eum_data_permission_grant/listByRuleId", ["ruleId": ruleId]),
              let arr = data as? [Any] else { return [] }
        return arr.compactMap { $0 as? [String: Any] }.map(PermissionGrant.init)
    }

    func permissionGrantList(userId: Int) async -> [PermissionGrant] {
        guard let data = try? await api.post("eum_data_permission_grant/listByEumRbacUserId", ["eumRbacUserId": userId]),
              let arr = data as? [Any] else { return [] }
        return arr.compactMap { $0 as? [String: Any] }.map(PermissionGrant.init)
    }

    func permissionGrantInsert(ruleId: Int, userId: Int?, roleId: Int?, deptId: Int?) async throws {
        var body: [String: Any] = ["ruleId": ruleId]
        if let userId { body["eumRbacUserId"] = userId }
        if let roleId { body["eumRbacRoleId"] = roleId }
        if let deptId { body["eumRbacDeptId"] = deptId }
        try await api.post("eum_data_permission_grant/insert", body)
    }

    func permissionGrantDelete(ids: [Int]) async throws {
        try await api.post("eum_data_permission_grant/delete", ["grantIdList": ids])
    }

    // MARK: - 数据权限例外（eum_data_permission_exception）

    func permissionExceptionList(ruleId: Int) async -> [PermissionException] {
        guard let data = try? await api.post("eum_data_permission_exception/listByRuleId", ["ruleId": ruleId]),
              let arr = data as? [Any] else { return [] }
        return arr.compactMap { $0 as? [String: Any] }.map(PermissionException.init)
    }

    func permissionExceptionList(userId: Int) async -> [PermissionException] {
        guard let data = try? await api.post("eum_data_permission_exception/listByEumRbacUserId", ["eumRbacUserId": userId]),
              let arr = data as? [Any] else { return [] }
        return arr.compactMap { $0 as? [String: Any] }.map(PermissionException.init)
    }

    func permissionExceptionInsert(ruleId: Int, userId: Int?, roleId: Int?, deptId: Int?, exceptionType: Int) async throws {
        var body: [String: Any] = ["ruleId": ruleId, "exceptionType": exceptionType]
        if let userId { body["eumRbacUserId"] = userId }
        if let roleId { body["eumRbacRoleId"] = roleId }
        if let deptId { body["eumRbacDeptId"] = deptId }
        try await api.post("eum_data_permission_exception/insert", body)
    }

    func permissionExceptionDelete(ids: [Int]) async throws {
        try await api.post("eum_data_permission_exception/delete", ["exceptionIdList": ids])
    }

    // MARK: - 数据访问日志（eum_log_data_access）

    func accessLogPage(page: Int, size: Int, userId: Int?, resourceType: String, result: Int?) async throws -> PageResult<AccessLog> {
        var extra: [String: Any] = ["resourceType": resourceType]
        if let userId { extra["eumRbacUserId"] = userId }
        if let result { extra["result"] = result }
        let data = try await api.post("eum_log_data_access/page", pageBody(page: page, size: size, extra: extra))
        return PageResult.parse(data, AccessLog.init)
    }

    func accessLogList(userId: Int) async -> [AccessLog] {
        guard let data = try? await api.post("eum_log_data_access/listByEumRbacUserId", ["eumRbacUserId": userId]),
              let arr = data as? [Any] else { return [] }
        return arr.compactMap { $0 as? [String: Any] }.map(AccessLog.init)
    }

    func accessLogList(resourceType: String, resourceId: Int) async -> [AccessLog] {
        guard let data = try? await api.post("eum_log_data_access/listByResource", [
            "resourceType": resourceType, "resourceId": resourceId,
        ]), let arr = data as? [Any] else { return [] }
        return arr.compactMap { $0 as? [String: Any] }.map(AccessLog.init)
    }

    func accessLogRecord(userId: Int, resourceType: String, resourceId: Int?, action: String,
                         result: Int, ipAddress: String? = nil) async throws {
        var body: [String: Any] = [
            "eumRbacUserId": userId, "resourceType": resourceType,
            "action": action, "result": result,
        ]
        if let resourceId { body["resourceId"] = resourceId }
        if let ipAddress, !ipAddress.isEmpty { body["ipAddress"] = ipAddress }
        try await api.post("eum_log_data_access/insert", body)
    }

    // MARK: - 权限变更日志（eum_log_permission_change）

    func permissionLogPage(page: Int, size: Int, userId: Int?, changeType: String) async throws -> PageResult<PermissionChangeLog> {
        var extra: [String: Any] = ["changeType": changeType]
        if let userId { extra["eumRbacUserId"] = userId }
        let data = try await api.post("eum_log_permission_change/page", pageBody(page: page, size: size, extra: extra))
        return PageResult.parse(data, PermissionChangeLog.init)
    }

    func permissionLogList(userId: Int) async -> [PermissionChangeLog] {
        guard let data = try? await api.post("eum_log_permission_change/listByEumRbacUserId", ["eumRbacUserId": userId]),
              let arr = data as? [Any] else { return [] }
        return arr.compactMap { $0 as? [String: Any] }.map(PermissionChangeLog.init)
    }

    func permissionLogList(targetUserId: Int) async -> [PermissionChangeLog] {
        guard let data = try? await api.post("eum_log_permission_change/listByTargetUser", ["targetEumRbacUserId": targetUserId]),
              let arr = data as? [Any] else { return [] }
        return arr.compactMap { $0 as? [String: Any] }.map(PermissionChangeLog.init)
    }

    func permissionLogList(targetRoleId: Int) async -> [PermissionChangeLog] {
        guard let data = try? await api.post("eum_log_permission_change/listByTargetRole", ["targetEumRbacRoleId": targetRoleId]),
              let arr = data as? [Any] else { return [] }
        return arr.compactMap { $0 as? [String: Any] }.map(PermissionChangeLog.init)
    }

    func permissionLogRecord(userId: Int, targetUserId: Int?, targetRoleId: Int?, changeType: String,
                             resourceType: String, resourceId: Int?, oldValue: String, newValue: String) async throws {
        var body: [String: Any] = [
            "eumRbacUserId": userId, "changeType": changeType,
            "resourceType": resourceType, "oldValue": oldValue, "newValue": newValue,
        ]
        if let targetUserId { body["targetEumRbacUserId"] = targetUserId }
        if let targetRoleId { body["targetEumRbacRoleId"] = targetRoleId }
        if let resourceId { body["resourceId"] = resourceId }
        try await api.post("eum_log_permission_change/insert", body)
    }

    // MARK: - 关联表（角色-菜单 / 角色-部门 / 用户-角色）

    /// §4.22 角色已绑定的菜单 ID（关联表口径，作为 detail 的兜底来源）
    func roleMenuIds(roleId: Int) async -> [Int] {
        guard let data = try? await api.post("eum_rbac_role_menu/getByEumRbacRoleId", ["eumRbacRoleId": roleId])
        else { return [] }
        return JV.intArray(JV.dict(data)["eumRbacMenuIdList"])
    }

    /// §4.22 覆盖式保存角色菜单（先清空后写入）
    func roleMenuSave(roleId: Int, menuIds: [Int]) async throws {
        try? await api.post("eum_rbac_role_menu/delete", ["eumRbacRoleId": roleId])
        try await api.post("eum_rbac_role_menu/insert", ["eumRbacRoleId": roleId, "eumRbacMenuIdList": menuIds])
    }

    /// §4.21 角色自定义数据范围的部门 ID
    func roleDeptIds(roleId: Int) async -> [Int] {
        guard let data = try? await api.post("eum_rbac_role_dept/getByEumRbacRoleId", ["eumRbacRoleId": roleId])
        else { return [] }
        return JV.intArray(JV.dict(data)["eumRbacDeptIdList"])
    }

    /// §4.21 覆盖式保存角色部门（数据范围为「自定义」时使用）
    func roleDeptSave(roleId: Int, deptIds: [Int]) async throws {
        try? await api.post("eum_rbac_role_dept/delete", ["eumRbacRoleId": roleId])
        try await api.post("eum_rbac_role_dept/insert", ["eumRbacRoleId": roleId, "eumRbacDeptIdList": deptIds])
    }

    /// §4.24 用户已绑定的角色 ID（关联表口径）
    func userRoleIds(userId: Int) async -> [Int] {
        guard let data = try? await api.post("eum_rbac_user_role/getByEumRbacUserId", ["eumRbacUserId": userId])
        else { return [] }
        return JV.intArray(JV.dict(data)["eumRbacRoleIdList"])
    }

    /// §4.24 覆盖式保存用户角色（与 userInsert/userUpdate 的批量字段等价，供增量授权使用）
    func userRoleSave(userId: Int, roleIds: [Int]) async throws {
        try? await api.post("eum_rbac_user_role/delete", ["eumRbacUserId": userId])
        try await api.post("eum_rbac_user_role/insert", ["eumRbacUserId": userId, "eumRbacRoleIdList": roleIds])
    }

    // MARK: - 账号管理（account，§4.1）

    func accountPage(page: Int, size: Int, account: String) async throws -> PageResult<Account> {
        let data = try await api.post("account/page", pageBody(page: page, size: size, extra: ["account": account]))
        return PageResult.parse(data, Account.init)
    }

    func accountDetail(id: Int) async throws -> Account {
        let data = try await api.post("account/accountId", ["accountId": id])
        return Account(dict: JV.dict(data))
    }

    /// §4.1.1 插入 DTO 要求 accountId 必填（NotNull），由调用方传入
    func accountInsert(id: Int, account: String, password: String) async throws {
        try await api.post("account/insert", ["accountId": id, "account": account, "password": password])
    }

    func accountUpdate(id: Int, account: String?, password: String?) async throws {
        var body: [String: Any] = ["accountId": id]
        if let account, !account.isEmpty { body["account"] = account }
        if let password, !password.isEmpty { body["password"] = password }
        try await api.post("account/update", body)
    }

    func accountDelete(ids: [Int]) async throws {
        try await api.post("account/delete", ["accountIdList": ids])
    }

    // MARK: - Calcite 跨库查询（api/calcite，§4.2 / §4.3）

    func calciteHealth() async throws -> [String: Any] {
        JV.dict(try await api.get("api/calcite/v2/health"))
    }

    func calciteDataSources() async -> [String: Any] {
        guard let data = try? await api.get("api/calcite/v2/datasources") else { return [:] }
        return JV.dict(data)
    }

    func calciteSchemas() async -> [String] {
        guard let data = try? await api.get("api/calcite/schemas"), let arr = data as? [Any] else { return [] }
        return arr.compactMap { JV.string($0) }
    }

    /// §4.3.6 动态执行 SQL，返回行集（List<Map>）
    func calciteExecute(sql: String) async throws -> [[String: Any]] {
        let data = try await api.post("api/calcite/v2/execute", ["sql": sql])
        return JV.dictArray(data)
    }

    // MARK: - LangGraph（langgraph，§4.26）

    func langGraphInfo() async -> [String: Any] {
        guard let data = try? await api.get("langgraph/info") else { return [:] }
        return JV.dict(data)
    }

    /// §4.26.2 创建线程（body 为自由 Map，通常传 metadata）
    func langGraphCreateThread(metadata: [String: Any] = [:]) async throws -> [String: Any] {
        JV.dict(try await api.post("langgraph/threads", metadata))
    }

    /// §4.26.4 检索线程列表（LangGraph SDK 风格 limit/offset）
    func langGraphSearchThreads(limit: Int = 20, offset: Int = 0) async -> [[String: Any]] {
        guard let data = try? await api.post("langgraph/threads/search", ["limit": limit, "offset": offset])
        else { return [] }
        return JV.dictArray(data)
    }

    func langGraphThreadState(threadId: String) async throws -> [String: Any] {
        JV.dict(try await api.get("langgraph/threads/\(threadId)/state"))
    }

    func langGraphThreadHistory(threadId: String) async -> [[String: Any]] {
        guard let data = try? await api.get("langgraph/threads/\(threadId)/history") else { return [] }
        return JV.dictArray(data)
    }

    /// §4.26.6 流式运行（POST + SSE）。body 为自由 Map（input / assistant_id 等）
    func langGraphStreamRun(threadId: String, body: [String: Any],
                            onChunk: @escaping (String) -> Void) async throws {
        try await api.streamSSE(method: .post,
                                path: "langgraph/threads/\(threadId)/runs/stream",
                                body: body, onChunk: onChunk)
    }

    // MARK: - 授权 / 设备：设备侧接口补全（§4.27）

    func licenseDetail(machineId: String) async throws -> License {
        let data = try await api.get("licenses/\(machineId)")
        return License(dict: JV.dict(data))
    }

    func licenseDetail(key: String) async throws -> License {
        let data = try await api.get("licenses/key/\(key)")
        return License(dict: JV.dict(data))
    }

    /// §4.27.5 设备主动绑定（参数走 query）
    func licenseBind(licenseKey: String, machineId: String, deviceName: String? = nil) async throws {
        var query = ["licenseKey": licenseKey, "machineId": machineId]
        if let deviceName, !deviceName.isEmpty { query["deviceName"] = deviceName }
        try await api.request(.post, "licenses/bind", query: query, body: nil)
    }

    func licenseUnbind(licenseKey: String, machineId: String) async throws {
        try await api.post("licenses/unbind", ["licenseKey": licenseKey, "machineId": machineId])
    }

    /// §4.27.8 客户端激活（返回含机器指纹的离线证书）
    func activateDevice(licenseKey: String, machineId: String) async throws -> [String: Any] {
        let data = try await api.post("licenses/activate", ["licenseKey": licenseKey, "machineId": machineId])
        return JV.dict(data)
    }

    func pluginDetail(pluginId: String) async throws -> Plugin {
        let data = try await api.get("plugins/market/\(pluginId)")
        return Plugin(dict: JV.dict(data))
    }
}
