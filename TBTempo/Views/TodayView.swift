import SwiftData
import SwiftUI

struct TodayView: View {
    @Binding var selectedTab: AppTab
    @Query(sort: \Show.title) private var shows: [Show]
    @State private var showingSearch = false

    private var active: [Show] { shows.filter { $0.libraryState == .active } }
    private var nextUp: [(Show, Episode)] {
        active.compactMap { show in show.nextUp.map { (show, $0) } }
            .sorted { ($0.0.lastActivityAt ?? .distantPast) > ($1.0.lastActivityAt ?? .distantPast) }
    }
    private var recentlyWatched: [(Show, Episode, Date)] {
        shows.flatMap { show in
            show.episodes.compactMap { episode in
                episode.watchEvents.map(\.watchedAt).max().map { (show, episode, $0) }
            }
        }.sorted { $0.2 > $1.2 }.prefix(6).map { $0 }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if shows.isEmpty {
                    emptyState
                } else {
                    if !nextUp.isEmpty {
                        sectionHeader(String(localized: "Next Up"), subtitle: String(localized: "Keep your rhythm"))
                        ForEach(nextUp.prefix(8), id: \.1.id) { show, episode in
                            NavigationLink(value: show) {
                                EpisodeCard(episode: episode, showTitle: show.title, prominent: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !recentlyWatched.isEmpty {
                        sectionHeader(String(localized: "Recently Watched"), subtitle: nil)
                        ForEach(recentlyWatched, id: \.1.id) { show, episode, _ in
                            NavigationLink(value: show) {
                                EpisodeCard(episode: episode, showTitle: show.title)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !active.isEmpty {
                        sectionHeader(String(localized: "Active Series"), subtitle: String(localized: "Your current rotation"))
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 14) {
                                ForEach(active) { show in
                                    NavigationLink(value: show) {
                                        VStack(alignment: .leading, spacing: 8) {
                                            PosterView(show: show, width: 126)
                                            Text(show.title)
                                                .font(.subheadline.weight(.semibold))
                                                .lineLimit(2)
                                                .frame(width: 126, alignment: .leading)
                                            ProgressPill(watched: show.watchedRegularEpisodes.count, total: show.regularEpisodes.count)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "TB Tempo"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingSearch = true } label: { Label(String(localized: "Find a series"), systemImage: "plus") }
            }
        }
        .navigationDestination(for: Show.self) { SeriesDetailView(show: $0) }
        .sheet(isPresented: $showingSearch) { NavigationStack { SearchCatalogView() } }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "Your next episode starts here"), systemImage: "play.rectangle.on.rectangle")
        } description: {
            Text(String(localized: "Follow a series, or bring over your TV Time history when you’re ready."))
        } actions: {
            Button(String(localized: "Search for a Series")) { showingSearch = true }
                .buttonStyle(.borderedProminent)
            Button(String(localized: "Open Importer in Settings")) { selectedTab = .settings }
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func sectionHeader(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title2.bold())
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }
    }
}
