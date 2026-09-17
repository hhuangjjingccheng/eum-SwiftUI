import SwiftUI

// MARK: - Color(hex:)

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    init(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "#", with: "")
        if s.count == 8 { s = String(s.prefix(6)) }
        let v = UInt32(s, radix: 16) ?? 0x000000
        self.init(hex: v)
    }
}

// MARK: - EUM 线框设计体系（对应 eum-front src/style.css）

enum Theme {
    /// 主题色覆盖值（来自系统全局配置 sys/config 的 themeColor，如 "#409EFF"）
    /// nil = 线框默认黑 #171717。设置页保存 / bootstrap 加载后调用 applyThemeColor 生效
    private static var overridePrimaryHex: Int?

    /// 应用主题色（非法 / 空值回退默认黑）
    static func applyThemeColor(_ hexString: String?) {
        let s = (hexString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("#"), s.count == 7, let v = Int(s.dropFirst(), radix: 16) else {
            overridePrimaryHex = nil
            return
        }
        overridePrimaryHex = v
    }

    /// 主操作色：有覆盖值时全局动态生效（按钮 / FAB / 页签 / 复选框等）
    static var primary: Color {
        guard let hex = overridePrimaryHex else { return Color(hex: 0x171717) }
        return Color(hex: UInt32(hex))
    }
    static var primaryLight3: Color { tintedShade(0x525252, mix: 0.25) }
    static var primaryLight5: Color { tintedShade(0xA3A3A3, mix: 0.60) }
    static var primaryLight9: Color { tintedShade(0xFAFAFA, mix: 0.96) }

    /// 主色衍生浅阶：无覆盖返回线框默认灰阶；有覆盖时向白色按 mix 比例混合
    private static func tintedShade(_ fallback: UInt32, mix: Double) -> Color {
        guard let base = overridePrimaryHex else { return Color(hex: fallback) }
        func mixed(_ shift: UInt32) -> Int {
            let c = Double((base >> shift) & 0xFF)
            return Int((c + (255.0 - c) * mix).rounded())
        }
        let r = mixed(16), g = mixed(8), b = mixed(0)
        return Color(hex: UInt32((r << 16) | (g << 8) | b))
    }

    /// 页面背景
    static let pageBG = Color(hex: 0xF9FAFB)
    /// 面板背景
    static let panelBG = Color.white
    /// 边框
    static let border = Color(hex: 0xE5E7EB)
    static let borderLight = Color(hex: 0xF3F4F6)
    /// 正文
    static let text = Color(hex: 0x1F2937)
    static let textSecondary = Color(hex: 0x6B7280)
    static let textTertiary = Color(hex: 0x9CA3AF)

    /// 表头
    static let tableHeaderBG = Color(hex: 0x1F2937)
    static let tableHeaderBorder = Color(hex: 0x374151)

    /// 认证页 IBM Carbon 蓝
    static let authBlue = Color(hex: 0x0F62FE)
    static let authFieldBG = Color(hex: 0xF2F4F8)
    static let authText = Color(hex: 0x21272A)
    static let authHint = Color(hex: 0x697077)
    static let authLink = Color(hex: 0x001D6C)

    /// 状态色
    static let success = Color(hex: 0x67C23A)
    static let successLight = Color(hex: 0xF0F9EB)
    static let danger = Color(hex: 0xF56C6C)
    static let dangerLight = Color(hex: 0xFEF0F0)
    static let warning = Color(hex: 0xE6A23C)
    static let warningLight = Color(hex: 0xFDF6EC)
    static let info = Color(hex: 0x909399)
    static let infoLight = Color(hex: 0xF4F4F5)
    static let linkBlue = Color(hex: 0x409EFF)

    static let monoDark = Color(hex: 0x282C34)
    static let monoText = Color(hex: 0xABB2BF)

    static let panelRadius: CGFloat = 8
    static let gap: CGFloat = 12

    static func statusText(_ status: Int) -> String { L(status == 1 ? "eum.status.enable" : "eum.status.disable") }
}

// MARK: - 常用字体

extension Font {
    static let wireTitle = Font.system(size: 17, weight: .bold)
    static let wireCell = Font.system(size: 13)
    static let wireCellBold = Font.system(size: 13, weight: .semibold)
    static let wireCaption = Font.system(size: 12)
}

extension View {
    /// 面板阴影 0 1px 4px rgba(0,0,0,0.05)
    func panelShadow() -> some View {
        shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}
