import SwiftUI

enum AppTab: Hashable {
    case today
    case upcoming
    case shows
    case statistics
    case settings
}

struct RootTabView: View {
    @State private var selection: AppTab = .today
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selection) {
            Tab(String(localized: "Today"), systemImage: "sparkles.tv", value: AppTab.today) {
                NavigationStack { TodayView(selectedTab: $selection) }
            }
            Tab(String(localized: "Upcoming"), systemImage: "calendar.badge.clock", value: AppTab.upcoming) {
                NavigationStack { UpcomingView() }
            }
            Tab(String(localized: "Shows"), systemImage: "rectangle.stack", value: AppTab.shows) {
                NavigationStack { ShowsView() }
            }
            Tab(String(localized: "Statistics"), systemImage: "chart.bar.xaxis", value: AppTab.statistics) {
                NavigationStack { StatisticsView() }
            }
            Tab(String(localized: "Settings"), systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tint(Brand.coral)
        .safeAreaInset(edge: .bottom, spacing: 0) { UndoBar() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await dependencies.refresh.refreshIfNeeded() }
            }
        }
    }
}
