import SwiftUI

// MARK: - 个人中心

struct ProfileView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService

    @State private var editing = false
    @State private var nickName = ""
    @State private var realName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var menuExpanded = true

    private var user: SysUser { app.currentUser }

    private var genderText: String { user.gender == 1 ? "男" : (user.gender == 0 ? "女" : "未知") }
    private var genderIcon: String { user.gender == 1 ? "figure.stand" : (user.gender == 0 ? "figure.dress.line.vertical.figure" : "person") }

    var body: some View {
        PageLayout(header: headerBar) {
            WireCard(fullHeight: true) {
                VStack(spacing: 0) {
                    if editing {
                        editSection
                    } else {
                        detailSection
                    }
                    Divider()
                    menuPermSection
                }
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(LinearGradient(colors: [Theme.primary, Theme.primaryLight3], startPoint: .top, endPoint: .bottom))
                .frame(width: 4, height: 18)
            Text("详情").font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.text)
            Spacer()
            WireButton(title: L("button.refresh"), icon: "refresh", variant: .defaultPlain, small: true) {
                app.toastSuccess("已刷新")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.panelBG)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderLight).frame(height: 1) }
        .clipShape(RoundedCorner(radius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
        .panelShadow()
    }

    // MARK: 详情态（窄屏堆叠 / 宽屏左右分栏）
    @Environment(\.horizontalSizeClass) private var hSize

    private var detailSection: some View {
        Group {
            if hSize == .regular {
                HStack(alignment: .top, spacing: 0) {
                    profileSidebar
                        .frame(width: 240)
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(Theme.borderLight).frame(width: 1)
                        }
                    profileDetails
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    profileSidebar
                    profileDetails
                }
            }
        }
        .background(Theme.panelBG)
    }

    private var profileSidebar: some View {
        VStack(spacing: 12) {
            // 左侧档案
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Theme.primaryLight5, Theme.primary],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 88, height: 88)
                    Text(String(user.username.prefix(1)).uppercased())
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(.white)
                }
                Text(user.username)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(Theme.text)
                Text(user.nickName.isEmpty ? "暂无昵称" : user.nickName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.success)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Theme.successLight)
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.success, style: StrokeStyle(lineWidth: 1, dash: [3])))
                    .clipShape(RoundedCorner(radius: 20))

                Rectangle()
                    .fill(LinearGradient(colors: [.clear, Theme.border, .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
                    .padding(.horizontal, 30)

                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Theme.pageBG).frame(width: 32, height: 32)
                        Image(systemName: genderIcon).font(.system(size: 15)).foregroundColor(Theme.textSecondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("性别").font(.system(size: 11)).foregroundColor(Theme.textTertiary)
                        Text(genderText).font(.system(size: 13, weight: .medium)).foregroundColor(Theme.text)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .overlay(alignment: .bottom) {
                // 分栏模式由外层画竖线，堆叠模式画横线
                if hSize == .regular { EmptyView() }
                else { Rectangle().fill(Theme.borderLight).frame(height: 1) }
            }
        }
    }

    private var profileDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("详情").font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                    Spacer()
                    WireButton(title: L("button.edit"), icon: "create", variant: .primary, small: true) {
                        nickName = user.nickName
                        realName = user.realName
                        phone = user.phone
                        email = user.email
                        editing = true
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    profileCell(icon: "person", label: "用户名", value: user.username, highlight: true)
                    profileCell(icon: genderIcon, label: "性别", value: genderText)
                    profileCell(icon: "location", label: "所属部门", value: store.deptName(user.deptId))
                    profileCell(icon: "person", label: L("eum.user.read.nickName"), value: user.nickName.isEmpty ? "-" : user.nickName)
                    profileCell(icon: "person", label: L("eum.user.read.realName"), value: user.realName.isEmpty ? "-" : user.realName)
                    profileCell(icon: "call", label: L("eum.user.read.phone"), value: user.phone)
                    profileCell(icon: "mail", label: "邮箱", value: user.email, span: true)
                    profileCell(icon: "person.2", label: "所属角色", value: store.roleNames(user.roleIds), span: true)
                    profileCell(icon: "briefcase", label: "所属岗位", value: store.postNames(user.postIds), span: true)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func profileCell(icon: String, label: String, value: String, highlight: Bool = false, span: Bool = false) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Theme.pageBG).frame(width: 34, height: 34)
                WireIcon.image(icon, size: 15, color: Theme.textSecondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 11)).foregroundColor(Theme.textTertiary)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(highlight ? Theme.primary : Theme.text)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: span ? .infinity : .infinity, alignment: .leading)
        .background(Theme.pageBG.opacity(0.6))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.borderLight, lineWidth: 1))
    }

    // MARK: 编辑态
    private var editSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("详情").font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                Spacer()
                WireButton(title: L("button.cancel"), variant: .defaultPlain, small: true) { editing = false }
                WireButton(title: L("button.confirm"), variant: .primary, small: true) { Task { await save() } }
            }
            ScrollView {
                VStack(spacing: 14) {
                    FormTextField(label: L("eum.user.read.nickName"), placeholder: String(format: L("eum.placeholder.inputFormat"), L("eum.user.read.nickName")), text: $nickName)
                    FormTextField(label: L("eum.user.read.realName"), placeholder: String(format: L("eum.placeholder.inputFormat"), L("eum.user.read.realName")), text: $realName)
                    FormTextField(label: L("eum.user.read.phone"), placeholder: String(format: L("eum.placeholder.inputFormat"), L("eum.user.read.phone")), text: $phone)
                    FormTextField(label: L("eum.user.read.email"), placeholder: "请输入邮箱", text: $email)
                }
                .padding(.bottom, 10)
            }
            .frame(maxHeight: 260)
        }
        .padding(20)
    }

    private func save() async {
        guard email.isEmpty || email.contains("@") else { app.toastError("请输入正确的邮箱格式"); return }
        guard phone.isEmpty || phone.range(of: "^1[3-9]\\d{9}$", options: .regularExpression) != nil else {
            app.toastError("手机号码格式不正确")
            return
        }
        do {
            var updated = user
            updated.nickName = nickName
            updated.realName = realName
            updated.phone = phone
            updated.email = email
            try await store.updateProfile(updated, password: nil)
            // 重新拉取用户信息（脱敏回显以服务端为准）
            try await DataService.shared.bootstrap()
            editing = false
            app.toastSuccess("个人资料更新成功")
        } catch {
            app.toast(error, fallback: "保存失败")
        }
    }

    // MARK: 菜单权限树
    private var menuPermSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { menuExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    WireIcon.image("menu", size: 14, color: Theme.textSecondary)
                    Text("菜单权限").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)
                        .rotationEffect(.degrees(menuExpanded ? 180 : 0))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if menuExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(store.menus.sorted { $0.orderNum < $1.orderNum }) { menu in
                        profileMenuNode(menu, depth: 0)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
    }

    private func profileMenuNode(_ menu: SysMenu, depth: Int) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    if !menu.children.isEmpty {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Theme.textTertiary)
                    } else {
                        Circle().fill(Theme.border).frame(width: 4, height: 4).padding(.horizontal, 5)
                    }
                    Text(menu.translatedName)
                        .font(.system(size: 12.5))
                        .foregroundColor(Theme.text)
                    StatusTag(text: menu.menuTypeText, kind: menu.menuType == 1 ? .primary : (menu.menuType == 2 ? .success : .warning))
                }
                .padding(.leading, CGFloat(depth) * 18)
                .padding(.vertical, 4)

                ForEach(menu.children.sorted { $0.orderNum < $1.orderNum }) { child in
                    profileMenuNode(child, depth: depth + 1)
                }
            }
        )
    }
}
