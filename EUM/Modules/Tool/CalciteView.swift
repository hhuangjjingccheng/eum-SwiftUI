import SwiftUI

// MARK: - 数据查询（Calcite 跨库，api/calcite，§4.2 / §4.3）

/// 面向运维的跨库 SQL 调试台：健康检查、数据源 / Schema 总览、动态 SQL 执行。
struct CalciteView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: DataService

    @State private var health: [String: Any] = [:]
    @State private var dataSources: [String: Any] = [:]
    @State private var schemas: [String] = []
    @State private var sql = "SELECT 1"
    @State private var columns: [TableCol] = []
    @State private var rows: [[String: Any]] = []
    @State private var running = false
    @State private var lastError = ""

    var body: some View {
        PageLayout(header: headerSection) {
            VStack(spacing: Theme.gap) {
                statusCard
                sqlCard
                resultCard
            }
        }
        .task { await refreshMeta() }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            QueryForm {
                QueryField(label: L("calcite.sqlEditable"), text: .constant(sql))
            } onSearch: {
                Task { await refreshMeta() }
            } onReset: {
                Task { await refreshMeta() }
            }
        }
    }

    private var statusCard: some View {
        WireCard(title: "运行状态") {
            HStack(spacing: 14) {
                if lastError.isEmpty {
                    StatusTag(text: health.isEmpty ? "未检测" : "连接正常", kind: health.isEmpty ? .info : .success)
                } else {
                    StatusTag(text: "连接异常", kind: .danger)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(schemas, id: \.self) { s in
                            StatusTag(text: s, kind: .mono)
                        }
                        if schemas.isEmpty {
                            Text("暂无 Schema")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textTertiary)
                        }
                    }
                }
                Spacer()
                WireButton(title: L("button.refresh"), icon: "refresh", variant: .ghost, small: true) {
                    Task { await refreshMeta() }
                }
            }
            .padding(12)
            if !lastError.isEmpty {
                Text(lastError)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.danger)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
            if !dataSources.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(dataSources.keys.sorted(), id: \.self) { key in
                        HStack(alignment: .top, spacing: 6) {
                            Text(key)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(Theme.text)
                            Text(JSONSerialization.pretty(dataSources[key] ?? ""))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(Theme.textSecondary)
                                .lineLimit(2)
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 10)
            }
        }
    }

    private var sqlCard: some View {
        WireCard(title: "SQL 执行") {
            VStack(alignment: .leading, spacing: 10) {
                TextEditor(text: $sql)
                    .font(.system(size: 13, design: .monospaced))
                    .frame(minHeight: 88, maxHeight: 140)
                    .padding(6)
                    .background(Theme.panelBG)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.border, lineWidth: 1))
                HStack(spacing: 8) {
                    Text("POST /api/calcite/v2/execute")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.textTertiary)
                    Spacer()
                    WireButton(title: L("calcite.run"), icon: "play", variant: .primary, loading: running) {
                        Task { await execute() }
                    }
                }
            }
            .padding(12)
        }
    }

    private var resultCard: some View {
        WireCard(title: "结果（\(rows.count) 行）", fullHeight: true) {
            VStack(spacing: 0) {
                if rows.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tablecells")
                            .font(.system(size: 22))
                            .foregroundColor(Theme.textTertiary)
                        Text(running ? "执行中..." : "暂无结果")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 40)
                } else {
                    WireTable(columns: columns, rowCount: rows.count) { idx in
                        resultRow(idx)
                    }
                }
            }
        }
    }

    private func resultRow(_ idx: Int) -> some View {
        let row = rows[idx]
        return HStack(spacing: 0) {
            TableCell(text: "\(idx + 1)", width: 56, align: .center, color: Theme.textSecondary)
            ForEach(columns.dropFirst(), id: \.title) { col in
                TableCell(text: JV.string(row[col.title]), width: col.width, mono: true)
            }
        }
    }

    // MARK: 数据

    private func refreshMeta() async {
        do {
            health = try await store.calciteHealth()
            lastError = ""
        } catch {
            lastError = (error as? APIClient.ApiError)?.message ?? "健康检查失败"
            health = [:]
        }
        dataSources = await store.calciteDataSources()
        schemas = await store.calciteSchemas()
    }

    private func execute() async {
        let statement = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !statement.isEmpty else {
            app.toastWarning("请输入 SQL 语句")
            return
        }
        running = true
        defer { running = false }
        do {
            let result = try await store.calciteExecute(sql: statement)
            rows = result
            buildColumns(from: result)
            app.toastSuccess("执行成功，返回 \(result.count) 行")
        } catch {
            app.toast(error, fallback: "执行失败")
        }
    }

    /// 依据首行字段动态生成列（首列固定为行号）
    private func buildColumns(from rows: [[String: Any]]) {
        let keys = Array(rows.first?.keys.sorted() ?? []).prefix(10)
        columns = [.init("#", 56, align: .center)]
            + keys.map { .init($0, 150) }
    }
}
