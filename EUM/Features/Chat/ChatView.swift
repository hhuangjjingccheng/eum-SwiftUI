import SwiftUI

// MARK: - 智能对话

struct ChatView: View {
    @EnvironmentObject var app: AppState
    @StateObject private var vm = ChatViewModel()

    var body: some View {
        HStack(spacing: 0) {
            sessionSidebar
            chatMain
        }
        .background(Theme.panelBG)
        .onAppear { vm.loadInitialModels() }
    }

    // MARK: 左侧会话列表
    private var sessionSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                WireButton(title: L("chat.newSession"), icon: "add", variant: .primary, small: true) {
                    vm.createNewSession(toast: { app.toastInfo($0) })
                }
            }
            .padding(12)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderLight).frame(height: 1) }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(vm.sessions) { session in
                        sessionItem(session)
                    }
                }
                .padding(8)
            }
        }
        .frame(width: 190)
        .background(Color(hex: 0xF5F7FA))
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.borderLight).frame(width: 1) }
    }

    private func sessionItem(_ session: ChatSession) -> some View {
        let isActive = vm.currentSessionId == session.id
        return Button {
            vm.switchSession(session.id, toast: { app.toastWarning($0) })
        } label: {
            HStack(spacing: 8) {
                WireIcon.image("chatbubble-ellipses", size: 14,
                               color: isActive ? Theme.linkBlue : Theme.textSecondary)
                Text(session.title)
                    .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? Theme.linkBlue : Color(hex: 0x606266))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(isActive ? Color(hex: 0xECF5FF) : .clear)
            .clipShape(RoundedCorner(radius: 6))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                vm.requestDelete(session.id, title: session.title, confirm: { confirmDel in
                    // 用 alert 呈现
                    vm.pendingDelete = session.id
                })
            } label: {
                Label("删除会话", systemImage: "trash")
            }
        }
    }

    // MARK: 右侧聊天区
    private var chatMain: some View {
        VStack(spacing: 0) {
            // 顶部配置
            HStack {
                Text(vm.currentSession?.title ?? "EUM AI")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: 0x303133))
                    .lineLimit(1)
                Spacer()
                Menu {
                    ForEach(vm.availableModels, id: \.modelCode) { m in
                        Button(m.modelName) { vm.selectedModel = m.modelCode }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(vm.selectedModel.isEmpty ? "选择模型" : vm.selectedModel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.textTertiary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Theme.pageBG)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                }
                .frame(maxWidth: 170)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderLight).frame(height: 1) }

            // 消息列表
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        if vm.currentMessages.isEmpty {
                            VStack(spacing: 10) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 34))
                                    .foregroundColor(Theme.textTertiary)
                                Text("开始新的对话吧")
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.textTertiary)
                            }
                            .padding(.top, 60)
                        }
                        ForEach(vm.currentMessages) { msg in
                            messageBubble(msg)
                                .id(msg.id)
                        }
                        if vm.isStreaming {
                            HStack {
                                typingIndicator
                                Spacer()
                            }
                            .padding(.leading, 56)
                        }
                        Color.clear.frame(height: 4).id("bottom")
                    }
                    .padding(20)
                }
                .onChange(of: vm.lastStreamedContent) { _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: vm.isStreaming) { _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }

            // 输入区
            VStack(spacing: 10) {
                TextField("您的问题，按发送按钮发送", text: $vm.inputMessage, axis: .vertical)
                    .font(.system(size: 13))
                    .lineLimit(1...4)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.pageBG)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                HStack {
                    Spacer()
                    WireButton(title: L("chat.send"), icon: "paper-plane", variant: .primary,
                               disabled: vm.inputMessage.trimmingCharacters(in: .whitespaces).isEmpty || vm.isStreaming) {
                        Task { await vm.sendMessage() }
                    }
                }
            }
            .padding(14)
            .overlay(alignment: .top) { Rectangle().fill(Theme.borderLight).frame(height: 1) }
        }
        .background(Theme.panelBG)
        .alert("删除确认", isPresented: Binding(
            get: { vm.pendingDelete != nil },
            set: { if !$0 { vm.pendingDelete = nil } }
        )) {
            Button(L("button.delete"), role: .destructive) {
                vm.deleteSession(vm.pendingDelete ?? "")
                vm.pendingDelete = nil
            }
            Button(L("button.cancel"), role: .cancel) { vm.pendingDelete = nil }
        } message: {
            Text("确定要删除该会话吗？")
        }
    }

    private func messageBubble(_ msg: ChatMessage) -> some View {
        let isUser = msg.role == "user"
        return HStack(alignment: .top, spacing: 14) {
            if isUser { Spacer(minLength: 24) }
            ZStack {
                Circle()
                    .fill(isUser ? Theme.linkBlue : Color(hex: 0xF0F2F5))
                    .frame(width: 38, height: 38)
                WireIcon.image(isUser ? "person" : "desktop", size: 18,
                               color: isUser ? .white : Color(hex: 0x606266))
            }
            if !isUser { Spacer(minLength: 24) }
            Text(msg.content.isEmpty ? " " : msg.content)
                .font(.system(size: 13.5))
                .foregroundColor(Color(hex: 0x303133))
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: 380, alignment: .leading)
                .background(isUser ? Color(hex: 0xECF5FF) : Color(hex: 0xF4F4F5))
                .clipShape(RoundedCorner(radius: 8))
                .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color(hex: 0x909399))
                    .frame(width: 6, height: 6)
                    .scaleEffect(vm.typingPhase == i ? 1.0 : 0.5)
                    .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.16), value: vm.typingPhase)
            }
        }
        .padding(14)
        .background(Color(hex: 0xF4F4F5))
        .clipShape(RoundedCorner(radius: 8))
        .onAppear { vm.startTypingAnimation() }
    }
}

// MARK: - Chat 状态机

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var sessions: [ChatSession] = [
        ChatSession(id: "s1", title: "新会话", messages: []),
    ]
    @Published var currentSessionId = "s1"
    @Published var inputMessage = ""
    @Published var isStreaming = false
    @Published var selectedModel = ""
    @Published var availableModels: [AIModel] = []
    @Published var typingPhase = 0
    @Published var pendingDelete: String?
    @Published var lastStreamedContent = ""

    private var typingTimer: Task<Void, Never>?

    var currentSession: ChatSession? {
        sessions.first { $0.id == currentSessionId }
    }

    var currentMessages: [ChatMessage] {
        currentSession?.messages ?? []
    }

    func loadInitialModels() {
        guard availableModels.isEmpty else { return }
        Task {
            do {
                let info = try await DataService.shared.chatModels()
                availableModels = info.models
                selectedModel = info.defaultModel.isEmpty ? (info.models.first?.modelCode ?? "") : info.defaultModel
            } catch {
                // 静默失败（未登录/无密钥时与 web 行为一致）
            }
        }
    }

    func createNewSession(toast: (String) -> Void) {
        if let empty = sessions.first(where: { $0.messages.isEmpty }) {
            currentSessionId = empty.id
            toast("已经是新会话啦，随时可以提问~")
            return
        }
        let s = ChatSession(id: UUID().uuidString, title: "新会话")
        sessions.insert(s, at: 0)
        currentSessionId = s.id
    }

    func switchSession(_ id: String, toast: (String) -> Void) {
        if isStreaming {
            toast("AI 正在回复中，请稍后再切换会话")
            return
        }
        currentSessionId = id
    }

    func requestDelete(_ id: String, title: String, confirm: (String) -> Void) {
        confirm(title)
    }

    func deleteSession(_ id: String) {
        sessions.removeAll { $0.id == id }
        if currentSessionId == id {
            if let first = sessions.first {
                currentSessionId = first.id
            } else {
                let s = ChatSession(id: UUID().uuidString, title: "新会话")
                sessions.append(s)
                currentSessionId = s.id
            }
        }
    }

    func startTypingAnimation() {
        typingTimer?.cancel()
        typingTimer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard let self else { return }
                self.typingPhase = (self.typingPhase + 1) % 3
            }
        }
    }

    func sendMessage() async {
        let content = inputMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isStreaming else { return }

        if let idx = sessions.firstIndex(where: { $0.id == currentSessionId }) {
            if sessions[idx].messages.isEmpty {
                sessions[idx].title = String(content.prefix(15)) + (content.count > 15 ? "..." : "")
            }
            sessions[idx].messages.append(ChatMessage(role: "user", content: content))
            sessions[idx].messages.append(ChatMessage(role: "assistant", content: ""))
        }
        inputMessage = ""
        isStreaming = true
        lastStreamedContent = ""
        let sessionId = currentSessionId
        let model = selectedModel

        func append(_ chunk: String) {
            if let idx = sessions.firstIndex(where: { $0.id == sessionId }),
               let last = sessions[idx].messages.indices.last {
                sessions[idx].messages[last].content += chunk
                lastStreamedContent = sessions[idx].messages[last].content
            }
        }

        do {
            try await APIClient.shared.streamSSE(
                path: "chat/stream",
                query: ["message": content, "sessionId": sessionId, "model": model]
            ) { chunk in
                append(chunk)
            }
        } catch {
            append("\n\n[网络请求失败]")
        }
        isStreaming = false
    }
}
