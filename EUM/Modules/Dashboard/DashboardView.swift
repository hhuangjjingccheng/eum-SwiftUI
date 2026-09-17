import SwiftUI

// MARK: - Dashboard

struct DashboardView: View {
    @EnvironmentObject var app: AppState
    @State private var viewModel = DashboardViewModel()

    private let stats: [(String, String, String)] = [
        ("dashboard.stat.users", "1,234", "person"),
        ("dashboard.stat.visits", "567", "eye"),
        ("dashboard.stat.orders", "890", "cart"),
        ("dashboard.stat.revenue", "¥12,345", "cash"),
    ]

    var body: some View {
        PageLayout(header: header) {
            VStack(spacing: 20) {
                // 统计卡片（宽屏多列网格，窄屏单列）
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                    ForEach(stats, id: \.0) { stat in
                        WireStatCard(title: L(stat.0), value: stat.1, icon: stat.2)
                    }
                }

                // 快捷操作
                WireCard(title: L("dashboard.quickActions")) {
                    VStack(alignment: .leading, spacing: 10) {
                        WireButton(title: String(format: L("dashboard.counter"), viewModel.counter), variant: .primary) {
                            withAnimation { viewModel.incrementCounter() }
                        }
                        WireButton(title: L("dashboard.addData"), variant: .defaultPlain) {
                            app.toastInfo(L("dashboard.mockAdd"))
                        }
                        WireButton(title: L("dashboard.viewReports"), variant: .ghost) {
                            app.toastInfo(L("dashboard.mockReports"))
                        }
                        WireButton(title: L("dashboard.systemSettings"), variant: .defaultPlain) {
                            app.navigate(to: .eumConfig)
                        }
                        .frame(maxWidth: 240, alignment: .leading)
                    }
                    .padding(16)
                }
            }
        }
    }

    private var header: some View {
        WirePageHeader(
            title: L("dashboard.title"),
            description: L("dashboard.subtitle")
        )
    }
}
