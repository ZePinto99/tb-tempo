import SwiftData
import SwiftUI

struct SeriesDetailView: View {
    @Bindable var show: Show
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var modelContext
    @State private var expandedSeasons = Set<Int>()
    @State private var showingCatalogMatch = false

    private var seasons: [Int] { Array(Set(show.episodes.map(\.seasonNumber))).sorted() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                synopsis
                controls
                ForEach(seasons, id: \.self) { season in seasonSection(season) }
            }
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(show.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCatalogMatch) {
            NavigationStack { SearchCatalogView(matchingShow: show) }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if show.tmdbID == nil {
                        Button(String(localized: "Match with TMDB"), systemImage: "link") { showingCatalogMatch = true }
                    }
                    if show.libraryState == .stopped {
                        Button(String(localized: "Resume Series"), systemImage: "play.fill") { setState(.active) }
                    } else {
                        Button(String(localized: "Stop Series"), systemImage: "pause.fill") { setState(.stopped) }
                    }
                    Button(String(localized: "Mark Completed"), systemImage: "checkmark.seal") { setState(.completed) }
                    Button(String(localized: "Refresh Metadata"), systemImage: "arrow.clockwise") {
                        Task { await dependencies.refresh.refresh([show]) }
                    }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            ArtworkView(data: show.backdropData, systemName: "tv")
                .frame(height: 270)
                .overlay(LinearGradient(colors: [.clear, Color(.systemGroupedBackground)], startPoint: .center, endPoint: .bottom))
            HStack(alignment: .bottom, spacing: 16) {
                PosterView(show: show, width: 112)
                VStack(alignment: .leading, spacing: 8) {
                    Text(show.title).font(.title.bold()).lineLimit(3)
                    Text(show.status.rawValue).font(.subheadline).foregroundStyle(.secondary)
                    ProgressPill(watched: show.watchedRegularEpisodes.count, total: show.regularEpisodes.count)
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder private var synopsis: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !show.genres.isEmpty { Text(show.genres.joined(separator: " · ")).font(.caption.weight(.semibold)).foregroundStyle(Brand.coral) }
            Text(show.overview.isEmpty ? String(localized: "Metadata will appear after a successful catalog refresh.") : show.overview)
                .font(.body)
                .foregroundStyle(show.overview.isEmpty ? .secondary : .primary)
        }
        .padding(.horizontal)
    }

    private var controls: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $show.notificationsEnabled) {
                Label(String(localized: "Release notifications"), systemImage: "bell")
            }
            .padding()
            Divider().padding(.leading)
            HStack {
                Label(show.libraryState.title, systemImage: show.libraryState == .stopped ? "pause.circle" : "play.circle")
                Spacer()
                if let date = show.nextRelease {
                    Text(CountdownFormatter.text(until: date)).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal)
        .onChange(of: show.notificationsEnabled) { _, _ in
            try? modelContext.save()
            Task { await dependencies.refresh.rescheduleNotificationsFromLibrary() }
        }
    }

    private func seasonSection(_ season: Int) -> some View {
        let episodes = show.episodes.filter { $0.seasonNumber == season }.sorted(by: Episode.canonicalOrder)
        let watched = episodes.filter(\.isWatched).count
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .snappy) {
                    if expandedSeasons.contains(season) { expandedSeasons.remove(season) } else { expandedSeasons.insert(season) }
                }
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(season == 0 ? String(localized: "Specials") : String(localized: "Season \(season)"))
                            .font(.title3.bold())
                        Text(String(localized: "\(watched) of \(episodes.count) watched"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button(String(localized: "Mark Season Watched"), systemImage: "checkmark.circle") {
                            dependencies.progress.setSeason(season, in: show, watched: true, context: modelContext)
                            Task { await dependencies.refresh.rescheduleNotificationsFromLibrary() }
                        }
                        Button(String(localized: "Mark Season Unwatched"), systemImage: "circle") {
                            dependencies.progress.setSeason(season, in: show, watched: false, context: modelContext)
                            Task { await dependencies.refresh.rescheduleNotificationsFromLibrary() }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").frame(width: 44, height: 44)
                    }
                    Image(systemName: expandedSeasons.contains(season) ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            if expandedSeasons.contains(season) {
                ForEach(episodes) { episode in
                    EpisodeCard(episode: episode, showTitle: show.title)
                        .contextMenu {
                            Button(String(localized: "Mark Through This Episode"), systemImage: "checkmark.circle.badge.questionmark") {
                                dependencies.progress.setThrough(episode, in: show, context: modelContext)
                                Task { await dependencies.refresh.rescheduleNotificationsFromLibrary() }
                            }
                            Button(episode.isCanceled ? String(localized: "Restore Upcoming Episode") : String(localized: "Mark as Canceled"), systemImage: episode.isCanceled ? "arrow.uturn.backward" : "calendar.badge.minus") {
                                episode.isCanceled.toggle()
                                try? modelContext.save()
                                Task { await dependencies.refresh.rescheduleNotificationsFromLibrary() }
                            }
                        }
                }
            }
        }
        .padding(.horizontal)
    }

    private func setState(_ state: LibraryState) {
        show.libraryState = state
        try? modelContext.save()
        Task { await dependencies.refresh.rescheduleNotificationsFromLibrary() }
    }
}
