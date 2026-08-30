import SwiftData
import SwiftUI

enum UpcomingPresentation: String, CaseIterable, Identifiable {
    case list
    case calendar
    var id: String { rawValue }
}

enum UpcomingGroup: Int, CaseIterable, Identifiable {
    case today
    case tomorrow
    case nextSeven
    case nextThirty
    case later

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .today: String(localized: "Today")
        case .tomorrow: String(localized: "Tomorrow")
        case .nextSeven: String(localized: "Next 7 Days")
        case .nextThirty: String(localized: "Next 30 Days")
        case .later: String(localized: "Later")
        }
    }
}

struct UpcomingView: View {
    @Query private var shows: [Show]
    @Environment(AppDependencies.self) private var dependencies
    @State private var search = ""
    @State private var selectedShowID: UUID?
    @AppStorage("upcomingPresentation") private var presentationRaw = UpcomingPresentation.list.rawValue

    private var presentation: UpcomingPresentation {
        get { UpcomingPresentation(rawValue: presentationRaw) ?? .list }
        nonmutating set { presentationRaw = newValue.rawValue }
    }

    private var candidates: [(Show, Episode)] {
        let calendar = Calendar.autoupdatingCurrent
        let today = calendar.startOfDay(for: Date())
        let horizon = calendar.date(byAdding: .day, value: 90, to: today) ?? today
        return shows.filter { $0.libraryState == .active }.flatMap { show in
            show.episodes.filter { episode in
                guard !episode.isWatched, !episode.isCanceled else { return false }
                guard selectedShowID == nil || selectedShowID == show.id else { return false }
                guard search.isEmpty || show.title.localizedStandardContains(search) || episode.title.localizedStandardContains(search) else { return false }
                guard let date = episode.airDate else { return episode.title.isEmpty == false && episode.tmdbID != nil }
                let day = calendar.startOfDay(for: date)
                return day >= today && day <= horizon
            }.map { (show, $0) }
        }.sorted { ($0.1.airDate ?? .distantFuture) < ($1.1.airDate ?? .distantFuture) }
    }

    var body: some View {
        Group {
            if candidates.isEmpty {
                ContentUnavailableView(
                    String(localized: "No releases in the next 90 days"),
                    systemImage: "calendar.badge.checkmark",
                    description: Text(String(localized: "Pull to refresh after following an active series."))
                )
            } else if presentation == .list {
                groupedList
            } else {
                calendarList
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "Upcoming"))
        .searchable(text: $search, prompt: String(localized: "Search releases"))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button(String(localized: "All series")) { selectedShowID = nil }
                    ForEach(shows.filter { $0.libraryState == .active }) { show in
                        Button(show.title) { selectedShowID = show.id }
                    }
                } label: { Label(String(localized: "Filter by series"), systemImage: "line.3.horizontal.decrease.circle") }
                Picker(String(localized: "Presentation"), selection: Binding(get: { presentation }, set: { presentation = $0 })) {
                    Image(systemName: "list.bullet").tag(UpcomingPresentation.list)
                    Image(systemName: "calendar").tag(UpcomingPresentation.calendar)
                }
                .pickerStyle(.segmented)
                .frame(width: 96)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { refreshStatus }
        .refreshable { await dependencies.refresh.refreshAll() }
    }

    private var groupedList: some View {
        List {
            ForEach(UpcomingGroup.allCases) { group in
                let entries = candidates.filter { upcomingGroup(for: $0.1.airDate) == group }
                if !entries.isEmpty {
                    Section(group.title) {
                        ForEach(entries, id: \.1.id) { show, episode in
                            NavigationLink { SeriesDetailView(show: show) } label: {
                                UpcomingRow(show: show, episode: episode)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var calendarList: some View {
        List {
            ForEach(Dictionary(grouping: candidates, by: { item in
                item.1.airDate.map { Calendar.autoupdatingCurrent.startOfDay(for: $0) }
            }).keys.sorted { ($0 ?? .distantFuture) < ($1 ?? .distantFuture) }, id: \.self) { date in
                Section(date.map { $0.formatted(date: .complete, time: .omitted) } ?? String(localized: "Date not confirmed")) {
                    ForEach(candidates.filter { item in item.1.airDate.map { Calendar.autoupdatingCurrent.startOfDay(for: $0) } == date }, id: \.1.id) { show, episode in
                        NavigationLink { SeriesDetailView(show: show) } label: { UpcomingRow(show: show, episode: episode) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var refreshStatus: some View {
        HStack(spacing: 8) {
            if dependencies.refresh.isRefreshing { ProgressView().controlSize(.small) }
            Image(systemName: isStale ? "exclamationmark.arrow.triangle.2.circlepath" : "checkmark.circle")
                .foregroundStyle(isStale ? .orange : .secondary)
            Text(refreshText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private var newestRefresh: Date? { shows.compactMap(\.lastMetadataRefresh).max() }
    private var isStale: Bool { newestRefresh.map { Date().timeIntervalSince($0) > 24 * 60 * 60 } ?? true }
    private var refreshText: String {
        if dependencies.refresh.isRefreshing { return String(localized: "Refreshing \(dependencies.refresh.completedCount) of \(dependencies.refresh.totalCount)…") }
        if let newestRefresh { return String(localized: "Updated \(newestRefresh.formatted(.relative(presentation: .named)))") }
        return String(localized: "Metadata has not been refreshed")
    }

    private func upcomingGroup(for date: Date?) -> UpcomingGroup {
        guard let days = CountdownFormatter.daysRemaining(until: date) else { return .later }
        switch days {
        case 0: return .today
        case 1: return .tomorrow
        case 2...7: return .nextSeven
        case 8...30: return .nextThirty
        default: return .later
        }
    }
}

private struct UpcomingRow: View {
    let show: Show
    let episode: Episode

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(data: episode.stillData ?? show.posterData, systemName: "calendar")
                .frame(width: 74, height: 74)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(show.title).font(.headline).lineLimit(1)
                Text("\(episode.coordinate) · \(episode.title)").font(.subheadline).lineLimit(2)
                Text(episode.airDate?.formatted(date: .abbreviated, time: .omitted) ?? String(localized: "Date not confirmed"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(CountdownFormatter.text(until: episode.airDate))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Brand.coral)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
