import SwiftUI

// MARK: - 仪表盘模块 · ViewModel（@Observable 细粒度刷新示范）

@Observable
@MainActor
final class DashboardViewModel {
    private(set) var counter = 0

    func incrementCounter() {
        counter += 1
    }
}
