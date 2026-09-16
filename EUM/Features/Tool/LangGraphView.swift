import SwiftUI

// MARK: - LangGraph 线程调试台（langgraph，§4.26）

/// 线程（threads）管理 + 状态 / 历史查看 + 流式运行控制台。
/// run 请求体为自由 Map（LangGraph input / assistant_id 等），以原始 JSON 编辑区透传。
struct LangGraphView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService

    @State private var info: [String: Any] = [:]
    @State private var threads: [[String: Any]] = []
    @State private var loading = false
    @State private var creating = false

    // 详情弹层
    @State private var detailThread: [String: Any]?
    @State private var detailState = ""
    @State private var detailHistory = ""
    @State private var detailLoading = false

    // 运行控制台
    @State private var runThreadId = ""
    @State private var runBody = """
    {
      "assistant_id": "",
      "input": { "messages": [ { "role": "user", "content": "你好" } ] }
    }
    """
    @State private var consoleText = ""
    @State private var streaming = false

    var body: some View {
        PageLayout(header: headerSection) {
            VStack(spacing: Theme.gap) {
                infoCard
                threadsCard
                runCard
            }
        }
        .sheet(item: Binding(
            get: { detailThread.map(DetailTarget.init) },
            set: { detailThread = $0?.thread }
        )) { target in
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Thread State")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.text)
                        Text(detailState.isEmpty ? "加载中..." : detailState)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                        Text("Thread History")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.text)
                        Text(detailHistory.isEmpty ? "加载中..." : detailHistory)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(16)
                }
                .navigationTitle("线程详情")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("关闭") { detailThread = nil }.font(.system(size: 13))
                    }
                }
                .task { await loadDetail(target.thread) }
            }
            .presentationDetents([.large])
        }
        .task { await refresh() }
    }

    private struct DetailTarget: Identifiable {
        let thread: [String: Any]
        var id: String { JV.string(thread["thread_id"]) }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            QueryForm {
                Text("POST SSE /langgraph/threads/{id}/runs/stream")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
            } onSearch: {
                Task { await refresh() }
            } onReset: {
                Task { await refresh() }
            }
        }
    }

    private var infoCard: some View {
        WireCard(title: "Graph 信息") {
            VStack(alignment: .leading, spacing: 6) {
                if info.isEmpty {
                    Text("暂无信息")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                } else {
                    Text(JSONSerialization.pretty(info))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(12)
        }
    }

    private var threadsCard: some View {
        WireCard(title: "线程（\(threads.count)）", fullHeight: true) {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    WireButton(title: L("langgraph.newThread"), icon: "add-circle", variant: .primary, small: true, loading: creating) {
                        Task { await createThread() }
                    }
                    WireButton(title: L("button.refresh"), icon: "refresh", variant: .ghost, small: true) {
                        Task { await refresh() }
                    }
                    Spacer()
                }
                .padding(12)

                if loading {
                    ProgressView().padding(.vertical, 24)
                } else if threads.isEmpty {
                    Text("暂无线程")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                        .padding(.vertical, 24)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(threads.enumerated()), id: \.offset) { _, thread in
                                threadRow(thread)
                            }
                        }
                    }
                }
            }
        }
    }

    private func threadRow(_ thread: [String: Any]) -> some View {
        let threadId = JV.string(thread["thread_id"])
        let createdAt = JV.string(thread["created_at"])
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(threadId.isEmpty ? "-" : threadId)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(createdAt.isEmpty ? "-" : createdAt)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
            WireButton(title: L("langgraph.run"), icon: "play", variant: .linkPrimary, small: true) {
                runThreadId = threadId
                consoleText = ""
            }
            WireButton(title: L("button.detail"), icon: "book", variant: .linkPlain, small: true) {
                detailThread = thread
                detailState = ""
                detailHistory = ""
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.borderLight).frame(height: 1) }
    }

    private var runCard: some View {
        WireCard(title: "流式运行\(runThreadId.isEmpty ? "" : " · \(runThreadId)")") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    FormFieldLabel(text: "Thread ID")
                    TextField("先从列表选择或手动输入", text: $runThreadId)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Theme.panelBG)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                }
                TextEditor(text: $runBody)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 96, maxHeight: 150)
                    .padding(6)
                    .background(Theme.panelBG)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                HStack {
                    Text("请求体 JSON 原样透传（input / assistant_id / stream_mode 等）")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                    Spacer()
                    WireButton(title: L("langgraph.stream"), icon: "play", variant: .primary, loading: streaming) {
                        Task { await run() }
                    }
                }
                if !consoleText.isEmpty {
                    ScrollView {
                        Text(consoleText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 200)
                    .padding(8)
                    .background(Theme.pageBG)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                }
            }
            .padding(12)
        }
    }

    // MARK: 数据

    private func refresh() async {
        loading = true
        defer { loading = false }
        info = await store.langGraphInfo()
        threads = await store.langGraphSearchThreads()
    }

    private func createThread() async {
        creating = true
        defer { creating = false }
        do {
            let thread = try await store.langGraphCreateThread()
            let threadId = JV.string(thread["thread_id"])
            app.toastSuccess("线程已创建：\(threadId.isEmpty ? "无 ID" : threadId)")
            threads = await store.langGraphSearchThreads()
        } catch {
            app.toast(error, fallback: "创建失败")
        }
    }

    private func loadDetail(_ thread: [String: Any]) async {
        let threadId = JV.string(thread["thread_id"])
        guard !threadId.isEmpty else {
            detailState = "{}"
            detailHistory = "[]"
            return
        }
        detailLoading = true
        defer { detailLoading = false }
        if let state = try? await store.langGraphThreadState(threadId: threadId) {
            detailState = JSONSerialization.pretty(state)
        }
        let history = await store.langGraphThreadHistory(threadId: threadId)
        detailHistory = JSONSerialization.pretty(history)
    }

    private func run() async {
        guard !runThreadId.isEmpty else {
            app.toastWarning("请先选择或输入 Thread ID")
            return
        }
        guard let data = runBody.data(using: .utf8),
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              JSONSerialization.isValidJSONObject(body)
        else {
            app.toastError("请求体不是合法的 JSON 对象")
            return
        }
        streaming = true
        consoleText = ""
        defer { streaming = false }
        do {
            try await store.langGraphStreamRun(threadId: runThreadId, body: body) { chunk in
                Task { @MainActor in
                    consoleText += chunk + "\n"
                }
            }
            if consoleText.isEmpty { consoleText = "（无流式输出）" }
        } catch {
            app.toast(error, fallback: "运行失败")
            consoleText += "⚠️ " + ((error as? APIClient.ApiError)?.message ?? "运行失败")
        }
    }
}
