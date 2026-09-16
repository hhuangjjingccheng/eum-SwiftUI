import Foundation

// MARK: - RBAC 系统管理模型（字段映射后端 JSON，属性名与页面保持一致）

struct SysUser: Identifiable, Equatable {
    var id: Int
    var username: String
    var nickName: String
    var realName: String
    var phone: String
    var email: String
    var gender: Int            // 1男 0女
    var status: Int            // 1启用 0停用
    var deptId: Int?
    var roleIds: [Int]
    var postIds: [Int]
    var remark: String
    var createTime: String
    var createBy: String

    init(dict: [String: Any]) {
        id = JV.int(dict["eumRbacUserId"]) ?? 0
        username = JV.string(dict["username"])
        nickName = JV.string(dict["nickName"])
        realName = JV.string(dict["realName"])
        phone = JV.string(dict["phone"])
        email = JV.string(dict["email"])
        gender = JV.int(dict["gender"]) ?? 1
        status = JV.int(dict["status"]) ?? 1
        deptId = JV.int(dict["eumRbacDeptId"])
        roleIds = JV.intArray(dict["eumRbacRoleIds"])
        postIds = JV.intArray(dict["eumRbacPostIds"])
        remark = JV.string(dict["remark"])
        createTime = JV.string(dict["createTime"])
        createBy = JV.string(dict["createBy"])
    }

    /// 本地构造（新增表单）
    init(id: Int, username: String, nickName: String, realName: String = "", phone: String = "", email: String = "",
         gender: Int = 1, status: Int = 1, deptId: Int? = nil, roleIds: [Int] = [], postIds: [Int] = [],
         remark: String = "", createTime: String = "", createBy: String = "") {
        self.id = id; self.username = username; self.nickName = nickName; self.realName = realName
        self.phone = phone; self.email = email; self.gender = gender; self.status = status
        self.deptId = deptId; self.roleIds = roleIds; self.postIds = postIds
        self.remark = remark; self.createTime = createTime; self.createBy = createBy
    }
}

struct SysRole: Identifiable, Equatable {
    var id: Int
    var roleName: String
    var roleKey: String
    var roleSort: Int
    var status: Int
    var menuIds: [Int]
    var remark: String
    var createTime: String
    var createBy: String

    init(dict: [String: Any]) {
        id = JV.int(dict["eumRbacRoleId"]) ?? 0
        roleName = JV.string(dict["roleName"])
        roleKey = JV.string(dict["roleKey"])
        roleSort = JV.int(dict["roleSort"]) ?? 1
        status = JV.int(dict["status"]) ?? 1
        menuIds = JV.intArray(dict["eumRbacMenuIds"])
        remark = JV.string(dict["remark"])
        createTime = JV.string(dict["createTime"])
        createBy = JV.string(dict["createBy"])
    }

    init(id: Int, roleName: String, roleKey: String, roleSort: Int = 1, status: Int = 1,
         menuIds: [Int] = [], remark: String = "", createTime: String = "", createBy: String = "admin") {
        self.id = id; self.roleName = roleName; self.roleKey = roleKey; self.roleSort = roleSort
        self.status = status; self.menuIds = menuIds; self.remark = remark
        self.createTime = createTime; self.createBy = createBy
    }
}

struct SysPost: Identifiable, Equatable {
    var id: Int
    var postName: String
    var postCode: String
    var postSort: Int
    var status: Int
    var remark: String
    var createTime: String
    var createBy: String

    init(dict: [String: Any]) {
        id = JV.int(dict["eumRbacPostId"]) ?? 0
        postName = JV.string(dict["postName"])
        postCode = JV.string(dict["postCode"])
        postSort = JV.int(dict["postSort"]) ?? 1
        status = JV.int(dict["status"]) ?? 1
        remark = JV.string(dict["remark"])
        createTime = JV.string(dict["createTime"])
        createBy = JV.string(dict["createBy"])
    }

    init(id: Int, postName: String, postCode: String, postSort: Int = 1, status: Int = 1,
         remark: String = "", createTime: String = "", createBy: String = "admin") {
        self.id = id; self.postName = postName; self.postCode = postCode; self.postSort = postSort
        self.status = status; self.remark = remark; self.createTime = createTime; self.createBy = createBy
    }
}

struct SysDept: Identifiable, Equatable {
    var id: Int
    var parentId: Int
    var ancestors: String
    var deptName: String
    var leader: String
    var phone: String
    var email: String
    var orderNum: Int
    var status: Int
    var children: [SysDept]
    var createTime: String

    init(dict: [String: Any]) {
        id = JV.int(dict["eumRbacDeptId"]) ?? 0
        parentId = JV.int(dict["parentId"]) ?? 0
        ancestors = JV.string(dict["ancestors"])
        deptName = JV.string(dict["deptName"])
        leader = JV.string(dict["leader"])
        phone = JV.string(dict["phone"])
        email = JV.string(dict["email"])
        orderNum = JV.int(dict["orderNum"]) ?? 0
        status = JV.int(dict["status"]) ?? 1
        children = JV.dictArray(dict["children"]).map(SysDept.init)
        createTime = JV.string(dict["createTime"])
    }

    init(id: Int, parentId: Int, ancestors: String = "", deptName: String, leader: String = "",
         phone: String = "", email: String = "", orderNum: Int = 0, status: Int = 1,
         children: [SysDept] = [], createTime: String = "") {
        self.id = id; self.parentId = parentId; self.ancestors = ancestors; self.deptName = deptName
        self.leader = leader; self.phone = phone; self.email = email; self.orderNum = orderNum
        self.status = status; self.children = children; self.createTime = createTime
    }

    func flattened() -> [SysDept] { [self] + children.flatMap { $0.flattened() } }
}

struct SysMenu: Identifiable, Equatable {
    var id: Int
    var parentId: Int
    var menuName: String
    var path: String
    var component: String
    var routeName: String
    var icon: String
    var menuType: Int          // 1目录 2菜单 3按钮
    var orderNum: Int
    var isFrame: Int           // 0是外链 1否
    var isCache: Int
    var visible: Int
    var status: Int
    var perms: String
    var children: [SysMenu]
    var createTime: String
    var remark: String

    init(dict: [String: Any]) {
        id = JV.int(dict["eumRbacMenuId"]) ?? 0
        parentId = JV.int(dict["parentId"]) ?? 0
        menuName = JV.string(dict["menuName"])
        path = JV.string(dict["path"])
        component = JV.string(dict["component"])
        routeName = JV.string(dict["routeName"])
        let rawIcon = JV.string(dict["icon"])
        icon = rawIcon.isEmpty ? "#" : rawIcon
        menuType = JV.int(dict["menuType"]) ?? 2
        orderNum = JV.int(dict["orderNum"]) ?? 0
        isFrame = JV.int(dict["isFrame"]) ?? 1
        isCache = JV.int(dict["isCache"]) ?? 1
        visible = JV.int(dict["visible"]) ?? 1
        status = JV.int(dict["status"]) ?? 1
        perms = JV.string(dict["perms"])
        children = JV.dictArray(dict["children"]).map(SysMenu.init)
        createTime = JV.string(dict["createTime"])
        remark = JV.string(dict["remark"])
    }

    init(id: Int, parentId: Int, menuName: String, path: String = "", component: String = "",
         routeName: String = "", icon: String = "#", menuType: Int = 2, orderNum: Int = 0,
         isFrame: Int = 1, isCache: Int = 1, visible: Int = 1, status: Int = 1,
         perms: String = "", children: [SysMenu] = [], createTime: String = "",
         remark: String = "") {
        self.id = id; self.parentId = parentId; self.menuName = menuName; self.path = path
        self.component = component; self.routeName = routeName; self.icon = icon
        self.menuType = menuType; self.orderNum = orderNum; self.isFrame = isFrame
        self.isCache = isCache; self.visible = visible; self.status = status; self.perms = perms
        self.children = children; self.createTime = createTime; self.remark = remark
    }

    var translatedName: String { I18n.t(menuName) }
    var menuTypeText: String { menuType == 1 ? "目录" : (menuType == 2 ? "菜单" : "按钮") }
}

struct SysDictType: Identifiable, Equatable {
    var id: Int
    var dictName: String
    var dictType: String
    var status: Int
    var remark: String
    var createTime: String

    init(dict: [String: Any]) {
        id = JV.int(dict["eumDictionaryTypeId"]) ?? 0
        dictName = JV.string(dict["dictName"])
        dictType = JV.string(dict["dictType"])
        status = JV.int(dict["status"]) ?? 1
        remark = JV.string(dict["remark"])
        createTime = JV.string(dict["createTime"])
    }

    init(id: Int, dictName: String, dictType: String, status: Int = 1, remark: String = "", createTime: String = "") {
        self.id = id; self.dictName = dictName; self.dictType = dictType
        self.status = status; self.remark = remark; self.createTime = createTime
    }
}

struct SysDictData: Identifiable, Equatable {
    var id: Int
    var typeId: Int
    var dictLabel: String
    var dictValue: String
    var i18nKey: String
    var dictSort: Int
    var status: Int
    var listClass: String
    var cssClass: String
    var remark: String

    init(dict: [String: Any]) {
        id = JV.int(dict["eumDictionaryDataId"]) ?? 0
        typeId = JV.int(dict["eumDictionaryTypeId"]) ?? 0
        dictLabel = JV.string(dict["dictLabel"])
        dictValue = JV.string(dict["dictValue"])
        i18nKey = JV.string(dict["i18nKey"])
        dictSort = JV.int(dict["dictSort"]) ?? 1
        status = JV.int(dict["status"]) ?? 1
        listClass = JV.string(dict["listClass"])
        cssClass = JV.string(dict["cssClass"])
        remark = JV.string(dict["remark"])
    }

    init(id: Int, typeId: Int, dictLabel: String, dictValue: String, i18nKey: String = "",
         dictSort: Int = 1, status: Int = 1, listClass: String = "default", cssClass: String = "", remark: String = "") {
        self.id = id; self.typeId = typeId; self.dictLabel = dictLabel; self.dictValue = dictValue
        self.i18nKey = i18nKey; self.dictSort = dictSort; self.status = status
        self.listClass = listClass; self.cssClass = cssClass; self.remark = remark
    }
}

// MARK: - AI 配置模型

struct AIProvider: Identifiable, Equatable {
    var id: Int
    var providerName: String
    var providerCode: String
    var baseUrl: String
    var status: Int
    var remark: String
    var createTime: String

    init(dict: [String: Any]) {
        id = JV.int(dict["eumAiProviderId"]) ?? 0
        providerName = JV.string(dict["providerName"])
        providerCode = JV.string(dict["providerCode"])
        baseUrl = JV.string(dict["baseUrl"])
        status = JV.int(dict["status"]) ?? 1
        remark = JV.string(dict["remark"])
        createTime = JV.string(dict["createTime"])
    }

    init(id: Int, providerName: String, providerCode: String, baseUrl: String,
         status: Int = 1, remark: String = "", createTime: String = "") {
        self.id = id; self.providerName = providerName; self.providerCode = providerCode
        self.baseUrl = baseUrl; self.status = status; self.remark = remark; self.createTime = createTime
    }
}

struct AIApiKey: Identifiable, Equatable {
    var id: Int
    var providerId: Int
    var apiKey: String
    var status: Int
    var remark: String
    var defaultModel: String
    var models: [AIModel]
    var createTime: String

    init(dict: [String: Any]) {
        id = JV.int(dict["eumAiApiKeyId"]) ?? 0
        providerId = JV.int(dict["eumAiProviderId"]) ?? 0
        apiKey = JV.string(dict["apiKey"])
        status = JV.int(dict["status"]) ?? 1
        remark = JV.string(dict["remark"])
        createTime = JV.string(dict["createTime"])
        if let m = dict["models"] as? [String: Any] {
            defaultModel = JV.string(m["defaultModel"])
            models = JV.dictArray(m["models"]).map(AIModel.init(dict:))
        } else {
            defaultModel = ""
            models = []
        }
    }

    init(id: Int, providerId: Int, apiKey: String, status: Int = 1, remark: String = "",
         defaultModel: String = "", models: [AIModel] = [], createTime: String = "") {
        self.id = id; self.providerId = providerId; self.apiKey = apiKey; self.status = status
        self.remark = remark; self.defaultModel = defaultModel; self.models = models; self.createTime = createTime
    }

    var apiKeyPrefix: String {
        apiKey.count > 22 ? String(apiKey.prefix(22)) + "…" : apiKey
    }
}

struct AIModel: Equatable {
    var modelName: String
    var modelCode: String

    init(dict: [String: Any]) {
        modelName = JV.string(dict["modelName"])
        modelCode = JV.string(dict["modelCode"])
    }

    init(modelName: String, modelCode: String) {
        self.modelName = modelName
        self.modelCode = modelCode
    }
}

struct AIApiKeyModel: Identifiable, Equatable {
    var id: Int
    var apiKeyId: Int
    var model: String
    var status: Int
    var remark: String
    var createTime: String

    init(dict: [String: Any]) {
        id = JV.int(dict["eumAiApiKeyModelId"]) ?? 0
        apiKeyId = JV.int(dict["eumAiApiKeyId"]) ?? 0
        model = JV.string(dict["model"])
        status = JV.int(dict["status"]) ?? 1
        remark = JV.string(dict["remark"])
        createTime = JV.string(dict["createTime"])
    }

    init(id: Int, apiKeyId: Int, model: String, status: Int = 1, remark: String = "", createTime: String = "") {
        self.id = id; self.apiKeyId = apiKeyId; self.model = model
        self.status = status; self.remark = remark; self.createTime = createTime
    }
}

// MARK: - 友来特健康数据模型

struct UralytUser: Identifiable, Equatable {
    var id: Int
    var username: String
    var phone: String
    var password: String
    var nickname: String
    var gender: String
    var status: String
    var avatar: String
    var createTime: String

    init(dict: [String: Any]) {
        id = JV.int(dict["uralytUserId"]) ?? 0
        username = JV.string(dict["username"])
        phone = JV.string(dict["phone"])
        password = JV.string(dict["password"])
        nickname = JV.string(dict["nickname"])
        gender = JV.string(dict["gender"])
        status = JV.string(dict["status"])
        avatar = JV.string(dict["avatar"])
        createTime = JV.string(dict["createTime"])
    }

    init(id: Int, username: String, phone: String, password: String = "", nickname: String,
         gender: String = "1", status: String = "1", avatar: String = "", createTime: String = "") {
        self.id = id; self.username = username; self.phone = phone; self.password = password
        self.nickname = nickname; self.gender = gender; self.status = status
        self.avatar = avatar; self.createTime = createTime
    }

    var genderText: String { gender == "1" ? "男" : (gender == "0" ? "女" : gender) }
    var statusText: String {
        switch status {
        case "1", "正常": return "正常"
        case "0": return "停用"
        default: return status
        }
    }
}

struct UricRecord: Identifiable, Equatable {
    var id: Int
    var userId: Int
    var recordDate: String
    var morningPh: String
    var noonPh: String
    var eveningPh: String
    var morningDosage: String
    var noonDosage: String
    var eveningDosage: String
    var notes: String
    var createTime: String

    init(dict: [String: Any]) {
        id = JV.int(dict["uralytPhRecordId"]) ?? 0
        userId = JV.int(dict["uralytUserId"]) ?? 0
        recordDate = JV.string(dict["recordDate"])
        morningPh = JV.string(dict["morningPh"])
        noonPh = JV.string(dict["noonPh"])
        eveningPh = JV.string(dict["eveningPh"])
        morningDosage = JV.string(dict["morningDosage"])
        noonDosage = JV.string(dict["noonDosage"])
        eveningDosage = JV.string(dict["eveningDosage"])
        notes = JV.string(dict["notes"])
        createTime = JV.string(dict["createTime"])
    }

    init(id: Int, userId: Int, recordDate: String, morningPh: String, noonPh: String, eveningPh: String,
         morningDosage: String = "", noonDosage: String = "", eveningDosage: String = "",
         notes: String = "", createTime: String = "") {
        self.id = id; self.userId = userId; self.recordDate = recordDate
        self.morningPh = morningPh; self.noonPh = noonPh; self.eveningPh = eveningPh
        self.morningDosage = morningDosage; self.noonDosage = noonDosage; self.eveningDosage = eveningDosage
        self.notes = notes; self.createTime = createTime
    }
}

struct MedicalRecord: Identifiable, Equatable {
    var id: Int
    var userId: Int
    var recordDate: String
    var recordType: String
    var indicators: String
    var doctorNotes: String
    var createTime: String

    init(dict: [String: Any]) {
        id = JV.int(dict["uralytMedicalRecordId"]) ?? 0
        userId = JV.int(dict["uralytUserId"]) ?? 0
        recordDate = JV.string(dict["recordDate"])
        recordType = JV.string(dict["recordType"])
        indicators = JV.string(dict["indicators"])
        doctorNotes = JV.string(dict["doctorNotes"])
        createTime = JV.string(dict["createTime"])
    }

    init(id: Int, userId: Int, recordDate: String, recordType: String, indicators: String,
         doctorNotes: String = "", createTime: String = "") {
        self.id = id; self.userId = userId; self.recordDate = recordDate; self.recordType = recordType
        self.indicators = indicators; self.doctorNotes = doctorNotes; self.createTime = createTime
    }
}

// MARK: - 应用管理模型

struct Device: Identifiable, Equatable {
    var id: Int
    var machineId: String
    var deviceName: String
    var email: String
    var licenseId: Int?
    var licenseKey: String
    var lastActiveTime: String
    var status: Int               // 1正常 其他=已解绑

    init(dict: [String: Any]) {
        id = JV.int(dict["id"]) ?? 0
        machineId = JV.string(dict["machineId"])
        deviceName = JV.string(dict["deviceName"])
        email = JV.string(dict["email"])
        licenseId = JV.int(dict["licenseId"])
        licenseKey = JV.string(dict["licenseKey"])
        lastActiveTime = JV.string(dict["lastActiveTime"])
        status = JV.int(dict["status"]) ?? 0
    }
}

struct License: Identifiable, Equatable {
    var id: Int
    var boundMachines: [String]
    var licenseType: String       // trial / pro / enterprise
    var maxDevices: Int?
    var licenseKey: String
    var status: Int               // 1正常 0已吊销
    var remark: String
    var issuedAt: String
    var expiresAt: String         // 空=永久

    init(dict: [String: Any]) {
        id = JV.int(dict["licenseId"]) ?? 0
        boundMachines = (dict["boundMachines"] as? [Any])?.compactMap { JV.string($0) } ?? []
        licenseType = JV.string(dict["licenseType"])
        maxDevices = JV.int(dict["maxDevices"])
        licenseKey = JV.string(dict["licenseKey"])
        status = JV.int(dict["status"]) ?? 1
        remark = JV.string(dict["remark"])
        issuedAt = JV.string(dict["issuedAt"])
        expiresAt = JV.string(dict["expiresAt"])
    }

    /// 本地构造（颁发后展示）
    init(id: Int, boundMachines: [String] = [], licenseType: String, maxDevices: Int?,
         licenseKey: String, status: Int = 1, remark: String = "", issuedAt: String, expiresAt: String) {
        self.id = id; self.boundMachines = boundMachines; self.licenseType = licenseType
        self.maxDevices = maxDevices; self.licenseKey = licenseKey; self.status = status
        self.remark = remark; self.issuedAt = issuedAt; self.expiresAt = expiresAt
    }

    var typeText: String { licenseType.uppercased() }
    var isTrial: Bool { licenseType == "trial" }
    var expireText: String { expiresAt.isEmpty ? "永久有效" : String(expiresAt.prefix(10)) }
}

struct Plugin: Identifiable, Equatable {
    var id: Int
    var pluginId: String
    var name: String
    var version: String
    var vendor: String
    var descriptionText: String
    var iconUrl: String
    var downloadUrl: String
    var requiresRestart: Bool
    var sessionBound: Bool
    var status: Int               // 0待处理 1已上架

    init(dict: [String: Any]) {
        id = JV.int(dict["pluginMarketId"]) ?? 0
        pluginId = JV.string(dict["pluginId"])
        name = JV.string(dict["name"])
        version = JV.string(dict["version"])
        vendor = JV.string(dict["vendor"])
        descriptionText = JV.string(dict["description"])
        iconUrl = JV.string(dict["iconUrl"])
        downloadUrl = JV.string(dict["downloadUrl"])
        requiresRestart = JV.bool(dict["requiresRestart"])
        sessionBound = JV.bool(dict["sessionBound"])
        status = JV.int(dict["status"]) ?? 0
    }

    init(id: Int, pluginId: String, name: String, version: String, vendor: String,
         descriptionText: String, iconUrl: String = "", downloadUrl: String = "",
         requiresRestart: Bool = false, sessionBound: Bool = false, status: Int = 1) {
        self.id = id; self.pluginId = pluginId; self.name = name; self.version = version
        self.vendor = vendor; self.descriptionText = descriptionText; self.iconUrl = iconUrl
        self.downloadUrl = downloadUrl; self.requiresRestart = requiresRestart
        self.sessionBound = sessionBound; self.status = status
    }

    var payload: [String: Any] {
        [
            "pluginMarketId": id,
            "pluginId": pluginId,
            "name": name,
            "version": version,
            "vendor": vendor,
            "description": descriptionText,
            "iconUrl": iconUrl,
            "downloadUrl": downloadUrl,
            "requiresRestart": requiresRestart,
            "sessionBound": sessionBound,
            "status": status,
        ]
    }
}

// MARK: - 字典 / 系统配置

struct DictOption: Identifiable, Equatable {
    var id: String { "\(label)_\(value)" }
    let label: String
    let value: Int
    let kind: StatusKind

    /// eum_status 字典（登录后从 /system/dict/data/type/eum_status 拉取覆盖）
    static var eumStatus: [DictOption] = [
        .init(label: "启用", value: 1, kind: .success),
        .init(label: "停用", value: 0, kind: .danger),
    ]

    static func kind(forListClass cls: String) -> StatusKind {
        switch cls {
        case "success": return .success
        case "danger": return .danger
        case "warning": return .warning
        case "info": return .info
        case "primary": return .primary
        default: return .primary
        }
    }
}

struct SysConfig {
    var configId: Int = 0
    var themeColor: String = "#409EFF"
    var assistantApiKeyId: Int?
    var language: String = "zh-CN"
    var languageJson: [String: Any] = [:]
}

// MARK: - 聊天

struct ChatMessage: Codable, Equatable, Identifiable {
    var id = UUID()
    var role: String        // user / assistant
    var content: String
}

struct ChatSession: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var messages: [ChatMessage] = []
}

// MARK: - 分页

/// §2.2 分页结果：Spring Data `Page<T>` 序列化（入参 pageNum 从 1 开始，出参 number 从 0 开始）
struct PageResult<T> {
    let content: [T]
    let total: Int
    /// 总页数（由 total/size 推导兜底）
    var totalPages: Int = 1
    /// 当前页码（后端返回，从 0 开始）
    var number: Int = 0
    /// 每页条数
    var size: Int = 0

    /// 解析 {content, totalElements, totalPages, number, size}（Spring Data 风格）
    /// 亦兼容 {content, page:{totalElements,…}} 与其他包装形式。
    static func parse(_ data: Any?, _ map: ([String: Any]) -> T) -> PageResult<T> {
        guard let d = data as? [String: Any] else { return .init(content: [], total: 0) }
        let rows = JV.dictArray(d["content"]).map(map)
        var total = JV.int(d["totalElements"]) ?? JV.int(d["total"]) ?? rows.count
        var totalPages = JV.int(d["totalPages"]) ?? 1
        let number = JV.int(d["number"]) ?? 0
        let size = JV.int(d["size"]) ?? JV.int(d["pageSize"]) ?? rows.count
        if let page = d["page"] as? [String: Any] {
            total = JV.int(page["totalElements"]) ?? total
            totalPages = JV.int(page["totalPages"]) ?? totalPages
        }
        if JV.int(d["totalPages"]) == nil && size > 0 {
            totalPages = max(1, (total + size - 1) / size)
        }
        return .init(content: rows, total: total, totalPages: totalPages, number: number, size: size)
    }
}
