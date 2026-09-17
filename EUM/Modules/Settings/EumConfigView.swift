import SwiftUI

// MARK: - 参数设置（系统全局配置）

struct EumConfigView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService
    @Environment(\.horizontalSizeClass) private var hSize

    private var isCompact: Bool { hSize == .compact }

    @State private var themeColor = "#409EFF"
    @State private var apiKeyId: Int?
    @State private var language = "zh-CN"
    @State private var mode = "visual"   // visual / json
    @State private var jsonText = "{}"
    @State private var searchKey = ""
    @State private var showAddLanguage = false
    @State private var newLanguage = ""
    @State private var languageError = ""
    @State private var saving = false
    @State private var loading = false
    @State private var switchingLanguage = false

    /// 主题色预设（对齐 web 端；首个为线框默认黑）
    private static let themePresets: [(hex: String, name: String)] = [
        ("#171717", "config.theme.preset.black"),
        ("#409EFF", "config.theme.preset.blue"),
        ("#1E6FFF", "config.theme.preset.brand"),
        ("#67C23A", "config.theme.preset.green"),
        ("#E6A23C", "config.theme.preset.orange"),
        ("#F56C6C", "config.theme.preset.red"),
        ("#6366F1", "config.theme.preset.indigo"),
    ]

    private var languages: [String] {
        Array(store.sysConfig.languageJson.keys).sorted()
    }

    private var langTable: [String: [String: String]] {
        store.sysConfig.languageJson.compactMapValues { $0 as? [String: String] }
    }

    private var visualKeys: [String] {
        var keys = Set<String>()
        for (_, dict) in langTable { keys.formUnion(dict.keys) }
        return keys.sorted()
    }

    private var filteredKeys: [String] {
        visualKeys.filter { searchKey.isEmpty || $0.localizedCaseInsensitiveContains(searchKey) }
    }

    /// 语言选项：跟随系统 + languageJson 已配置语言
    private var languageOptions: [(code: String, label: String)] {
        [("system", L("config.lang.system"))] + I18n.availableLanguages.map { ($0, Self.languageLabel($0)) }
    }

    private static func languageLabel(_ code: String) -> String {
        switch code {
        case "zh-CN": return L("lang.zh-CN")
        case "en": return L("lang.en")
        case "ja": return L("lang.ja")
        default: return code
        }
    }

    private static func isDark(_ hex: String) -> Bool {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        let r = Double((v >> 16) & 0xFF), g = Double((v >> 8) & 0xFF), b = Double(v & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) < 140
    }

    /// 选中密钥解析详情（保存写入 sys/config 后由服务端 chat/stream 使用）
    private var selectedKey: AIApiKey? {
        store.apiKeys.first { $0.id == apiKeyId }
    }

    var body: some View {
        PageLayout(header: WirePageHeader(title: L("config.title"), description: L("config.subtitle"))) {
            if isCompact {
                // 手机端：分区卡片
                VStack(spacing: Theme.gap) {
                    WireCard { themeSection.padding(14) }
                    WireCard { aiSection.padding(14) }
                    WireCard { languageSection.padding(14) }
                    WireCard(title: "多语言高级配置") { advancedSection.padding(14) }
                }
            } else {
                // iPad / Mac：单卡分区
                WireCard(title: L("config.title")) {
                    VStack(alignment: .leading, spacing: 18) {
                        themeSection
                        Divider()
                        aiSection
                        Divider()
                        languageSection
                        Divider()
                        advancedSection
                    }
                    .padding(16)
                }
            }
        }
        .overlay { TableLoadingOverlay(loading: loading) }
        .overlay {
            if switchingLanguage {
                languageSwitchingOverlay
            }
        }
        .animation(.easeInOut(duration: 0.2), value: switchingLanguage)
        .task { await load() }
        // 离开页面时还原为已保存的主题色（未保存的预览色不落盘）
        .onDisappear { Theme.applyThemeColor(store.sysConfig.themeColor) }
        .alert(L("config.alert.addLang"), isPresented: $showAddLanguage) {
            TextField(L("config.alert.langPlaceholder"), text: $newLanguage)
            Button(L("button.confirm")) { addLanguage() }
            Button(L("button.cancel"), role: .cancel) {}
        } message: {
            Text(languageError.isEmpty ? L("config.alert.bcp47") : languageError)
        }
    }

    // MARK: 主题色（点选即时预览，保存写入 themeColor 全局生效）

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L("eum.tone"), subtitle: L("config.theme.subtitle"))
            HStack(spacing: isCompact ? 14 : 12) {
                ForEach(Self.themePresets, id: \.hex) { preset in
                    let isSelected = themeColor == preset.hex
                    Button {
                        themeColor = preset.hex
                        Theme.applyThemeColor(preset.hex)
                    } label: {
                        VStack(spacing: 5) {
                            Circle()
                                .fill(Color(hexString: preset.hex))
                                .frame(width: isCompact ? 32 : 28, height: isCompact ? 32 : 28)
                                .overlay(
                                    Circle().stroke(isSelected ? Theme.text : Theme.border, lineWidth: isSelected ? 2 : 1)
                                )
                                .overlay {
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(Self.isDark(preset.hex) ? .white : Theme.text)
                                    }
                                }
                            Text(L(preset.name))
                                .font(.system(size: 10))
                                .foregroundColor(isSelected ? Theme.text : Theme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(L("config.theme.current") + themeColor)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(Theme.textSecondary)
        }
    }

    // MARK: AI 助手密钥（写入 eumEumAiApiKey，服务端 chat/stream 按此转发）

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L("eum.ai.assistant.apiKey"), subtitle: L("config.ai.subtitle"))
            Picker("AI 助手的 APIKey", selection: $apiKeyId) {
                Text(L("eum.placeholder.select")).tag(Int?.none)
                ForEach(store.apiKeys) { key in
                    Text("\(store.providerName(key.providerId)) · \(key.apiKeyPrefix)").tag(Int?.some(key.id))
                }
            }
            .pickerStyle(.menu)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
            if let key = selectedKey {
                HStack(spacing: 6) {
                    StatusTag(text: store.providerName(key.providerId), kind: .primary)
                    StatusTag(text: L("config.ai.keyPrefix") + " \(key.apiKeyPrefix)···", kind: .mono)
                    if !key.defaultModel.isEmpty {
                        StatusTag(text: L("config.ai.defaultModel") + " \(key.defaultModel)", kind: .info)
                    }
                    StatusTag(text: String(format: L("config.ai.models"), key.models.count), kind: .mono)
                }
            } else if store.apiKeys.isEmpty {
                Text(L("config.ai.noKeys"))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            } else {
                Text(L("config.ai.noSelection"))
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }
        }
    }

    // MARK: 界面语言（写入 language，保存后翻译表与菜单立即生效）

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L("eum.language"), subtitle: L("config.lang.subtitle"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: isCompact ? 108 : 128), spacing: 8)], spacing: 8) {
                ForEach(languageOptions, id: \.code) { option in
                    let isSelected = option.code == "system" ? language == "system" : language == option.code
                    Button {
                        Task { await switchLanguage(to: option.code) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 12))
                                .foregroundColor(isSelected ? Theme.primary : Theme.textTertiary)
                            Text(option.label)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                                .foregroundColor(Theme.text)
                                .lineLimit(1)
                            if option.code == "system", language == "system" {
                                Text("(" + I18n.resolve("system", available: languages) + ")")
                                    .font(.system(size: 10))
                                    .foregroundColor(Theme.textTertiary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isSelected ? Theme.primaryLight9 : Theme.panelBG)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? Theme.primary : Theme.border, lineWidth: 1))
                        .clipShape(RoundedCorner(radius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .disabled(switchingLanguage)
        }
    }

    /// 语言切换转场：整页遮罩 + 转圈，完成后新语言文案填充
    private var languageSwitchingOverlay: some View {
        ZStack {
            Theme.pageBG.opacity(0.8)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(1.1)
                Text(L("config.lang.switching"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.text)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background(Theme.panelBG)
            .clipShape(RoundedCorner(radius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
            .panelShadow()
        }
        .transition(.opacity)
    }

    // MARK: 多语言高级配置（languageJson：可视化 / JSON 双模式）

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("config.adv.title"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.text)
                Spacer()
                Picker("模式", selection: $mode) {
                    Text(L("eum.visualization")).tag("visual")
                    Text(L("config.adv.json")).tag("json")
                }
                .pickerStyle(.segmented)
                .frame(width: isCompact ? 150 : 180)
            }

            if mode == "visual" {
                if isCompact {
                    visualEditorCompact
                } else {
                    visualEditor
                }
            } else {
                TextEditor(text: $jsonText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: isCompact ? 200 : 240)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(Theme.pageBG)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
            }

            HStack(spacing: 10) {
                WireButton(title: L("eum.addWord"), icon: "add-circle", variant: .defaultPlain, small: true) {
                    addWord()
                }
                WireButton(title: L("eum.addLanguage"), icon: "add", variant: .defaultPlain, small: true) {
                    newLanguage = ""; languageError = ""
                    showAddLanguage = true
                }
                Spacer()
                WireButton(title: L("eum.save"), variant: .primary, small: true, loading: saving) {
                    Task { await save() }
                }
            }
        }
    }

    /// 手机端词条编辑：一键一行（多语言宽表在窄屏放不下）
    private var visualEditorCompact: some View {
        VStack(alignment: .leading, spacing: 8) {
            MobileSearchBar(text: $searchKey, placeholder: L("config.adv.searchKey"), onFilter: {}, onSubmit: {})
            ForEach(filteredKeys, id: \.self) { key in
                VStack(alignment: .leading, spacing: 6) {
                    Text(key)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.text)
                    ForEach(languages, id: \.self) { lang in
                        HStack(spacing: 8) {
                            Text(lang)
                                .font(.system(size: 11))
                                .foregroundColor(Theme.textSecondary)
                                .frame(width: 60, alignment: .leading)
                            TextField(L("config.adv.textLabel"), text: visualValue(lang: lang, key: key))
                                .font(.system(size: 12))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Theme.pageBG)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                        }
                    }
                }
                .padding(10)
                .background(Theme.pageBG.opacity(0.4))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.borderLight, lineWidth: 1))
                .clipShape(RoundedCorner(radius: 6))
            }
            if filteredKeys.isEmpty {
                Text(visualKeys.isEmpty ? L("config.empty.words") : L("config.empty.noMatch"))
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            }
        }
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.text)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        async let cfgTask: Void = store.loadSysConfig()
        async let keysTask: Void = store.loadApiKeys()
        _ = await (cfgTask, keysTask)
        let cfg = store.sysConfig
        themeColor = cfg.themeColor
        apiKeyId = cfg.assistantApiKeyId
        language = cfg.language
        if let data = try? JSONSerialization.data(withJSONObject: cfg.languageJson, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            jsonText = text
        }
    }

    private func addWord() {
        let key = searchKey.isEmpty ? "menu.new\(Int(Date().timeIntervalSince1970))" : searchKey
        var json = store.sysConfig.languageJson
        for lang in languages {
            var dict = json[lang] as? [String: String] ?? [:]
            dict[key] = ""
            json[lang] = dict
        }
        store.sysConfig.languageJson = json
        if mode == "json" { syncJsonFromVisual() }
        app.toastSuccess(String(format: L("config.toast.wordAdded"), key))
    }

    private func addLanguage() {
        let pattern = "^[a-z]{2,3}(-[A-Z][a-z]{3})?(-[A-Z]{2})?$"
        guard newLanguage.range(of: pattern, options: .regularExpression) != nil else {
            languageError = L("config.alert.bcp47Error")
            showAddLanguage = true
            return
        }
        var json = store.sysConfig.languageJson
        json[newLanguage] = [String: String]()
        store.sysConfig.languageJson = json
        language = newLanguage
        if mode == "json" { syncJsonFromVisual() }
        app.toastSuccess(String(format: L("config.toast.langAdded"), newLanguage))
    }

    private func deleteLanguage(_ lang: String) {
        guard languages.count > 1 else { return }
        var json = store.sysConfig.languageJson
        json.removeValue(forKey: lang)
        store.sysConfig.languageJson = json
        if language == lang { language = "zh-CN" }
        if mode == "json" { syncJsonFromVisual() }
    }

    private func visualValue(lang: String, key: String) -> Binding<String> {
        Binding(
            get: { langTable[lang]?[key] ?? "" },
            set: { v in
                var json = store.sysConfig.languageJson
                var dict = json[lang] as? [String: String] ?? [:]
                dict[key] = v
                json[lang] = dict
                store.sysConfig.languageJson = json
            }
        )
    }

    private func syncJsonFromVisual() {
        if let data = try? JSONSerialization.data(withJSONObject: store.sysConfig.languageJson, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            jsonText = text
        }
    }

    private var visualEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            QueryField(label: L("eum.translateLable"), text: $searchKey)

            // 表头
            HStack(spacing: 0) {
                Text(L("eum.translateLable")).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                    .frame(width: 140, alignment: .leading).padding(.horizontal, 8)
                ForEach(languages, id: \.self) { lang in
                    HStack(spacing: 4) {
                        Text(lang).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                        if lang == language {
                            StatusTag(text: L("config.adv.default"), kind: .primary)
                        }
                        if languages.count > 1 {
                            Button {
                                deleteLanguage(lang)
                            } label: {
                                Text(L("common.delete")).font(.system(size: 11)).foregroundColor(Color(hex: 0xFCA5A5))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            }
            .padding(.vertical, 8)
            .background(Theme.tableHeaderBG)
            .clipShape(RoundedCorner(radius: 3))

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(visualKeys.filter { searchKey.isEmpty || $0.localizedCaseInsensitiveContains(searchKey) }, id: \.self) { key in
                        HStack(spacing: 0) {
                            Text(key)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Theme.text)
                                .frame(width: 140, alignment: .leading)
                                .padding(.horizontal, 8)
                            ForEach(languages, id: \.self) { lang in
                                TextField(L("config.adv.textLabel"), text: visualValue(lang: lang, key: key))
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 4)
                                    .background(Theme.pageBG)
                                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Theme.border, lineWidth: 1))
                                    .padding(.horizontal, 4)
                            }
                        }
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderLight).frame(height: 1) }
                    }
                }
            }
            .frame(maxHeight: 320)
        }
    }

    /// 点击语言选项 → 转圈 → 新语言填充 → 持久化（失败回滚并提示）
    private func switchLanguage(to code: String) async {
        let previous = language
        guard code != previous, !switchingLanguage else { return }
        switchingLanguage = true
        defer { switchingLanguage = false }
        // 1) 让转场可感知：短暂停留后执行切换
        try? await Task.sleep(nanoseconds: 550_000_000)
        // 2) 本地立即生效：翻译表 + Accept-Language + 全局取词刷新
        language = code
        var cfg = store.sysConfig
        cfg.language = code
        I18n.apply(languageJson: cfg.languageJson, language: code)
        APIClient.shared.language = I18n.language
        app.i18nVersion += 1
        // 3) 持久化到 sys/config；失败回滚到原语言
        do {
            try await store.saveSysConfig(cfg)
            store.sysConfig = cfg
            app.toastSuccess(L("config.toast.langSwitched"))
        } catch {
            language = previous
            I18n.apply(languageJson: store.sysConfig.languageJson, language: previous)
            app.i18nVersion += 1
            app.toast(error, fallback: L("config.error.save"))
        }
    }

    private func save() async {
        var cfg = store.sysConfig
        cfg.themeColor = themeColor
        cfg.assistantApiKeyId = apiKeyId
        cfg.language = language
        if mode == "json" {
            guard let data = jsonText.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data),
                  let parsed = obj as? [String: Any] else {
                app.toastError(L("config.toast.jsonError"))
                return
            }
            cfg.languageJson = parsed
        }
        saving = true
        defer { saving = false }
        do {
            try await store.saveSysConfig(cfg)
            store.sysConfig = cfg
            // 配置即时生效：
            // 1) themeColor → 全局主操作色  2) languageJson → I18n 取词表
            // 3) language（"system" 解析为具体码）→ Accept-Language  4) 重建侧边栏/页签重新取词
            Theme.applyThemeColor(cfg.themeColor)
            I18n.apply(languageJson: cfg.languageJson, language: cfg.language)
            APIClient.shared.language = I18n.language
            app.i18nVersion += 1
            app.toastSuccess(L("config.toast.saved"))
        } catch {
            app.toast(error, fallback: L("config.error.save"))
        }
    }
}
