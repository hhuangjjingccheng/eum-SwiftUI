import Foundation

// MARK: - 业务辅助

extension SysUser {
    /// 下拉选项展示名：昵称（用户名）
    var displayLabel: String {
        if nickName.isEmpty { return username }
        return "\(nickName)（\(username)）"
    }
}

// MARK: - 账号（account，§4.1）

struct Account: Identifiable, Equatable {
    var id: Int                  // accountId
    var account: String
    var password: String

    init(dict: [String: Any]) {
        id = JV.int(dict["accountId"]) ?? 0
        account = JV.string(dict["account"])
        password = JV.string(dict["password"])
    }

    init(id: Int = 0, account: String = "", password: String = "") {
        self.id = id; self.account = account; self.password = password
    }
}

// MARK: - JSON 美化（调试页展示原始结构）

extension JSONSerialization {
    static func pretty(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        else { return "\(value)" }
        return String(data: data, encoding: .utf8) ?? "\(value)"
    }
}

// MARK: - FXShell 异常管理（bovinishell）

struct FxshellLog: Identifiable, Equatable {
    var id: Int
    var errorLog: String
    var platform: String
    var isRepair: String          // 0 未修复 / 1 已修复
    var email: String
    var createTime: String
    var updateTime: String

    init(dict: [String: Any]) {
        id = JV.int(dict["eumFxshellId"]) ?? 0
        errorLog = JV.string(dict["errorLog"])
        platform = JV.string(dict["platform"])
        isRepair = JV.string(dict["isRepair"])
        email = JV.string(dict["email"])
        createTime = JV.string(dict["createTime"])
        updateTime = JV.string(dict["updateTime"])
    }

    init(id: Int = 0, errorLog: String = "", platform: String = "", isRepair: String = "0",
         email: String = "", createTime: String = "", updateTime: String = "") {
        self.id = id; self.errorLog = errorLog; self.platform = platform
        self.isRepair = isRepair; self.email = email
        self.createTime = createTime; self.updateTime = updateTime
    }

    var repairText: String { isRepair == "1" ? "已修复" : "未修复" }
    var repairKind: StatusKind { isRepair == "1" ? .success : .warning }
}

// MARK: - 客户 / 订单（biz_customer / biz_order）

struct BizCustomer: Identifiable, Equatable {
    var id: Int
    var customerName: String
    var contactPerson: String
    var contactPhone: String
    var contactEmail: String
    var address: String
    var ownerId: Int?
    var deptId: Int?
    var status: Int
    var remark: String
    var createTime: String
    var updateTime: String

    init(dict: [String: Any]) {
        id = JV.int(dict["customerId"]) ?? 0
        customerName = JV.string(dict["customerName"])
        contactPerson = JV.string(dict["contactPerson"])
        contactPhone = JV.string(dict["contactPhone"])
        contactEmail = JV.string(dict["contactEmail"])
        address = JV.string(dict["address"])
        ownerId = JV.int(dict["ownerId"])
        deptId = JV.int(dict["eumRbacDeptId"])
        status = JV.int(dict["status"]) ?? 1
        remark = JV.string(dict["remark"])
        createTime = JV.string(dict["createTime"])
        updateTime = JV.string(dict["updateTime"])
    }

    init(id: Int = 0, customerName: String = "", contactPerson: String = "", contactPhone: String = "",
         contactEmail: String = "", address: String = "", ownerId: Int? = nil, deptId: Int? = nil,
         status: Int = 1, remark: String = "", createTime: String = "", updateTime: String = "") {
        self.id = id; self.customerName = customerName; self.contactPerson = contactPerson
        self.contactPhone = contactPhone; self.contactEmail = contactEmail; self.address = address
        self.ownerId = ownerId; self.deptId = deptId; self.status = status
        self.remark = remark; self.createTime = createTime; self.updateTime = updateTime
    }
}

struct BizOrder: Identifiable, Equatable {
    var id: Int
    var orderNo: String
    var customerId: Int?
    var customerName: String
    var amount: String
    var status: Int            // OrderStatusEnum：0待支付 1已支付 2已取消
    var creatorId: Int?
    var deptId: Int?
    var remark: String
    var createTime: String
    var updateTime: String

    init(dict: [String: Any]) {
        id = JV.int(dict["orderId"]) ?? 0
        orderNo = JV.string(dict["orderNo"])
        customerId = JV.int(dict["customerId"])
        customerName = JV.string(dict["customerName"])
        amount = JV.string(dict["amount"])
        status = JV.int(dict["status"]) ?? 0
        creatorId = JV.int(dict["creatorId"])
        deptId = JV.int(dict["eumRbacDeptId"])
        remark = JV.string(dict["remark"])
        createTime = JV.string(dict["createTime"])
        updateTime = JV.string(dict["updateTime"])
    }

    init(id: Int = 0, orderNo: String = "", customerId: Int? = nil, customerName: String = "",
         amount: String = "0", status: Int = 0, creatorId: Int? = nil, deptId: Int? = nil,
         remark: String = "", createTime: String = "", updateTime: String = "") {
        self.id = id; self.orderNo = orderNo; self.customerId = customerId; self.customerName = customerName
        self.amount = amount; self.status = status; self.creatorId = creatorId; self.deptId = deptId
        self.remark = remark; self.createTime = createTime; self.updateTime = updateTime
    }

    /// §7.x OrderStatusEnum
    static let statusOptions: [DictOption] = [
        .init(label: "待支付", value: 0, kind: .warning),
        .init(label: "已支付", value: 1, kind: .success),
        .init(label: "已取消", value: 2, kind: .danger),
    ]

    var statusText: String {
        switch status {
        case 0: return "待支付"
        case 1: return "已支付"
        case 2: return "已取消"
        default: return "\(status)"
        }
    }

    var statusKind: StatusKind {
        switch status {
        case 0: return .warning
        case 1: return .success
        case 2: return .danger
        default: return .mono
        }
    }
}

// MARK: - 数据权限（eum_data_permission_*）

struct PermissionRule: Identifiable, Equatable {
    var id: Int                // ruleId
    var ruleName: String
    var resourceType: String
    var permissionType: Int    // 1读 2写 3删除 4审核
    var dataScope: Int         // 1全部 2自定义 3本部门 4本部门及子部门 5仅本人
    var status: Int
    var remark: String
    var createTime: String
    var updateTime: String

    init(dict: [String: Any]) {
        id = JV.int(dict["ruleId"]) ?? 0
        ruleName = JV.string(dict["ruleName"])
        resourceType = JV.string(dict["resourceType"])
        permissionType = JV.int(dict["permissionType"]) ?? 1
        dataScope = JV.int(dict["dataScope"]) ?? 1
        status = JV.int(dict["status"]) ?? 1
        remark = JV.string(dict["remark"])
        createTime = JV.string(dict["createTime"])
        updateTime = JV.string(dict["updateTime"])
    }

    init(id: Int = 0, ruleName: String = "", resourceType: String = "", permissionType: Int = 1,
         dataScope: Int = 1, status: Int = 1, remark: String = "", createTime: String = "", updateTime: String = "") {
        self.id = id; self.ruleName = ruleName; self.resourceType = resourceType
        self.permissionType = permissionType; self.dataScope = dataScope; self.status = status
        self.remark = remark; self.createTime = createTime; self.updateTime = updateTime
    }

    static let permissionTypes: [DictOption] = [
        .init(label: "读", value: 1, kind: .info),
        .init(label: "写", value: 2, kind: .primary),
        .init(label: "删除", value: 3, kind: .danger),
        .init(label: "审核", value: 4, kind: .warning),
    ]

    static let dataScopes: [DictOption] = [
        .init(label: "全部数据", value: 1, kind: .success),
        .init(label: "自定义", value: 2, kind: .primary),
        .init(label: "本部门", value: 3, kind: .info),
        .init(label: "本部门及子部门", value: 4, kind: .info),
        .init(label: "仅本人", value: 5, kind: .warning),
    ]

    func permissionTypeText(_ options: [DictOption] = permissionTypes) -> String {
        options.first { $0.value == permissionType }?.label ?? "\(permissionType)"
    }

    func dataScopeText(_ options: [DictOption] = dataScopes) -> String {
        options.first { $0.value == dataScope }?.label ?? "\(dataScope)"
    }
}

struct PermissionGrant: Identifiable, Equatable {
    var id: Int                // grantId
    var ruleId: Int
    var userId: Int?
    var roleId: Int?
    var deptId: Int?
    var createTime: String

    init(dict: [String: Any]) {
        id = JV.int(dict["grantId"]) ?? 0
        ruleId = JV.int(dict["ruleId"]) ?? 0
        userId = JV.int(dict["eumRbacUserId"])
        roleId = JV.int(dict["eumRbacRoleId"])
        deptId = JV.int(dict["eumRbacDeptId"])
        createTime = JV.string(dict["createTime"])
    }
}

struct PermissionException: Identifiable, Equatable {
    var id: Int                // exceptionId
    var ruleId: Int
    var userId: Int?
    var roleId: Int?
    var deptId: Int?
    var exceptionType: Int     // 例外类型：1白名单放通 2黑名单拦截
    var createTime: String

    init(dict: [String: Any]) {
        id = JV.int(dict["exceptionId"]) ?? 0
        ruleId = JV.int(dict["ruleId"]) ?? 0
        userId = JV.int(dict["eumRbacUserId"])
        roleId = JV.int(dict["eumRbacRoleId"])
        deptId = JV.int(dict["eumRbacDeptId"])
        exceptionType = JV.int(dict["exceptionType"]) ?? 1
        createTime = JV.string(dict["createTime"])
    }

    var exceptionTypeText: String { exceptionType == 1 ? "白名单（放通）" : "黑名单（拦截）" }
}

// MARK: - 审计日志（eum_log_*）

struct AccessLog: Identifiable, Equatable {
    var id: Int
    var userId: Int
    var resourceType: String
    var resourceId: Int?
    var action: String
    var result: Int            // 0失败 1成功
    var ipAddress: String
    var createTime: String

    init(dict: [String: Any]) {
        id = JV.int(dict["eumLogDataAccessId"]) ?? 0
        userId = JV.int(dict["eumRbacUserId"]) ?? 0
        resourceType = JV.string(dict["resourceType"])
        resourceId = JV.int(dict["resourceId"])
        action = JV.string(dict["action"])
        result = JV.int(dict["result"]) ?? 1
        ipAddress = JV.string(dict["ipAddress"])
        createTime = JV.string(dict["createTime"])
    }

    static let resultOptions: [DictOption] = [
        .init(label: "失败", value: 0, kind: .danger),
        .init(label: "成功", value: 1, kind: .success),
    ]
}

struct PermissionChangeLog: Identifiable, Equatable {
    var id: Int
    var userId: Int
    var targetUserId: Int?
    var targetRoleId: Int?
    var changeType: String     // grant / revoke / update
    var resourceType: String   // role / menu / dept
    var resourceId: Int?
    var oldValue: String
    var newValue: String
    var createTime: String

    init(dict: [String: Any]) {
        id = JV.int(dict["eumLogPermissionChangeId"]) ?? 0
        userId = JV.int(dict["eumRbacUserId"]) ?? 0
        targetUserId = JV.int(dict["targetEumRbacUserId"])
        targetRoleId = JV.int(dict["targetEumRbacRoleId"])
        changeType = JV.string(dict["changeType"])
        resourceType = JV.string(dict["resourceType"])
        resourceId = JV.int(dict["resourceId"])
        oldValue = JV.string(dict["oldValue"])
        newValue = JV.string(dict["newValue"])
        createTime = JV.string(dict["createTime"])
    }

    static let changeTypes: [DictOption] = [
        .init(label: "授权 grant", value: 1, kind: .success),
        .init(label: "撤销 revoke", value: 2, kind: .danger),
        .init(label: "变更 update", value: 3, kind: .info),
    ]

    var changeKind: StatusKind {
        switch changeType {
        case "revoke": return .danger
        case "update": return .info
        default: return .success
        }
    }
}
