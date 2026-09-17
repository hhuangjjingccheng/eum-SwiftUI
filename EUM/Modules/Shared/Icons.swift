import SwiftUI

/// 菜单/操作图标映射：Web 端 svg 名称 → SF Symbol
enum WireIcon {
    static func systemName(for name: String) -> String {
        switch name.lowercased() {
        case "dashboard": return "square.grid.2x2"
        case "user", "person": return "person"
        case "userfilled": return "person.2"
        case "menu": return "list.bullet"
        case "setting", "settings": return "gearshape"
        case "share": return "point.3.connected.trianglepath.dotted"
        case "postcard": return "rectangle.portrait.on.rectangle"
        case "collection": return "books.vertical"
        case "operation": return "slider.horizontal.3"
        case "dataline": return "chart.bar"
        case "histogram": return "chart.bar.doc.horizontal"
        case "firstaidkit": return "cross.case"
        case "chatdotround", "chatlineround": return "bubble.left.and.bubble.right"
        case "grid": return "square.grid.3x3"
        case "key": return "key"
        case "connection": return "link"
        case "monitor": return "desktopcomputer"
        case "iphone": return "iphone"
        case "cpu": return "cpu"
        case "search": return "magnifyingglass"
        case "search-circle": return "circle dotted" // fallback below
        case "add", "add-circle": return "plus.circle"
        case "delete": return "trash"
        case "pencil": return "pencil"
        case "book": return "book"
        case "close", "close-circle": return "xmark.circle"
        case "eye": return "eye"
        case "eye-off": return "eye.slash"
        case "person", "male": return "person"
        case "female": return "person"
        case "location": return "mappin.and.ellipse"
        case "call": return "phone"
        case "mail": return "envelope"
        case "create": return "square.and.pencil"
        case "list": return "list.bullet"
        case "chevron-forward": return "chevron.right"
        case "notifications": return "bell"
        case "cart": return "cart"
        case "cash": return "banknote"
        case "password-reset": return "key.horizontal"
        case "paper-plane": return "paperplane"
        case "chatbubble-ellipses": return "bubble.left"
        case "desktop": return "desktopcomputer"
        case "copy", "document-copy": return "doc.on.doc"
        case "refresh": return "arrow.clockwise"
        case "home": return "house"
        case "back": return "chevron.left"
        case "hand": return "hand.point.up.left"
        default: return "circle"
        }
    }

    static func image(_ name: String, size: CGFloat = 16, color: Color = Theme.textSecondary) -> some View {
        let resolved: String
        let n = name.lowercased()
        if n == "search-circle" {
            resolved = "magnifyingglass.circle"
        } else {
            resolved = systemName(for: name)
        }
        return Image(systemName: resolved)
            .font(.system(size: size))
            .foregroundColor(color)
    }
}
