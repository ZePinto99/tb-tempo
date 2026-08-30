import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class MetadataRefreshCoordinator {
    private let catalog: any CatalogProviding
    private let container: ModelContainer
    private let notificationScheduler: NotificationScheduling

    private(set) var isRefreshing = false
    private(set) var completedCount = 0
    private(set) var totalCount = 0
    private(set) var lastError: String?

    init(catalog: any CatalogProviding, container: ModelContainer, notificationScheduler: NotificationScheduling) {
        self.catalog = catalog
        self.container = container
        self.notificationScheduler = notificationScheduler
    }

    func refreshIfNeeded(maxAge: TimeInterval = 6 * 60 * 60) async {
        guard !isRefreshing else { return }
        let context = container.mainContext
        let shows = (try? context.fetch(FetchDescriptor<Show>())) ?? []
        let stale = shows.filter {
            guard $0.libraryState == .active else { return false }
            guard let last = $0.lastMetadataRefresh else { return true }
            return Date().timeIntervalSince(last) > maxAge
        }
        guard !stale.isEmpty else {
            await rescheduleNotifications(shows: shows)
            return
        }
        await refresh(stale)
    }

    func refreshAll() async {
        let shows = (try? container.mainContext.fetch(FetchDescriptor<Show>())) ?? []
        await refresh(shows)
    }

    func rescheduleNotificationsFromLibrary() async {
        let shows = (try? container.mainContext.fetch(FetchDescriptor<Show>())) ?? []
        await rescheduleNotifications(shows: shows)
    }

    func add(searchResult: CatalogSearchResult) async throws -> Show {
        let details = try await catalog.show(tmdbID: searchResult.id)
        let context = container.mainContext
        let show = upsert(details, existing: nil, in: context)
        show.libraryState = .active
        show.followedAt = Date()
        try await fetchArtwork(for: show)
        try context.save()
        await rescheduleNotifications(shows: (try? context.fetch(FetchDescriptor<Show>())) ?? [])
        return show
    }

    func refresh(_ shows: [Show]) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        completedCount = 0
        totalCount = shows.count
        defer { isRefreshing = false }

        for existing in shows {
            do {
                let tmdbID: Int
                var expectedTVDBID: Int?
                if let known = existing.tmdbID {
                    tmdbID = known
                } else if let tvdbID = existing.tvdbID,
                          let match = try await catalog.lookupTVDBSeries(id: tvdbID) {
                    tmdbID = match.id
                    expectedTVDBID = tvdbID
                } else {
                    throw CatalogError.noMatch
                }
                let details = try await catalog.show(tmdbID: tmdbID)
                if let expectedTVDBID, details.tvdbID != expectedTVDBID {
                    throw CatalogError.noMatch
                }
                _ = upsert(details, existing: existing, in: container.mainContext)
                try await resolveExternalEpisodeIDs(for: existing)
                try await fetchArtwork(for: existing)
                try container.mainContext.save()
            } catch {
                lastError = error.localizedDescription
            }
            completedCount += 1
        }
        let all = (try? container.mainContext.fetch(FetchDescriptor<Show>())) ?? []
        await rescheduleNotifications(shows: all)
    }

    @discardableResult
    private func upsert(_ details: CatalogShow, existing: Show?, in context: ModelContext) -> Show {
        let show: Show
        if let existing {
            show = existing
        } else {
            show = Show(title: details.title, tmdbID: details.tmdbID, tvdbID: details.tvdbID)
            context.insert(show)
        }
        show.title = details.title
        show.normalizedTitle = TextNormalizer.title(details.title)
        show.overview = details.overview
        show.status = details.status
        show.genres = details.genres
        show.tmdbID = details.tmdbID
        show.tvdbID = details.tvdbID ?? show.tvdbID
        show.posterPath = details.posterPath
        show.backdropPath = details.backdropPath
        show.defaultRuntimeMinutes = details.defaultRuntimeMinutes
        show.lastMetadataRefresh = Date()
        if details.status == .ended, show.progress >= 1 { show.libraryState = .completed }

        let byTMDB = Dictionary(uniqueKeysWithValues: show.episodes.compactMap { episode in episode.tmdbID.map { ($0, episode) } })
        var byCoordinate: [String: Episode] = [:]
        for episode in show.episodes {
            let key = "\(episode.seasonNumber):\(episode.episodeNumber)"
            if byCoordinate[key] == nil { byCoordinate[key] = episode }
        }
        for item in details.episodes {
            let coordinate = "\(item.seasonNumber):\(item.episodeNumber)"
            let episode = byTMDB[item.tmdbID] ?? byCoordinate[coordinate] ?? Episode(
                seasonNumber: item.seasonNumber,
                episodeNumber: item.episodeNumber,
                title: item.title,
                show: show
            )
            if episode.modelContext == nil {
                context.insert(episode)
                show.episodes.append(episode)
            }
            episode.title = item.title
            episode.overview = item.overview
            episode.tmdbID = item.tmdbID
            episode.tvdbID = episode.tvdbID ?? item.tvdbID
            episode.runtimeMinutes = item.runtimeMinutes
            episode.airDate = item.airDate
            episode.airDatePrecision = item.airDatePrecision
            episode.stillPath = item.stillPath
            episode.isSpecial = item.seasonNumber == 0
        }
        return show
    }

    private func fetchArtwork(for show: Show) async throws {
        if show.posterData == nil, let path = show.posterPath {
            show.posterData = try await catalog.imageData(path: path, width: 500)
        }
        if show.backdropData == nil, let path = show.backdropPath {
            show.backdropData = try await catalog.imageData(path: path, width: 780)
        }
    }

    private func resolveExternalEpisodeIDs(for show: Show) async throws {
        guard let showTVDBID = show.tvdbID else { return }
        let records = try container.mainContext.fetch(FetchDescriptor<UnresolvedImportRecord>()).filter {
            $0.tvdbSeriesID == showTVDBID && $0.tvdbEpisodeID != nil
        }
        guard !records.isEmpty else { return }
        var existingKeys = Set(try container.mainContext.fetch(FetchDescriptor<WatchEvent>()).map(\.stableKey))
        for record in records {
            guard let externalID = record.tvdbEpisodeID,
                  let mapped = try await catalog.lookupTVDBEpisode(id: externalID) else { continue }
            let exact = show.episodes.first { $0.tmdbID == mapped.tmdbID }
            let coordinateMatches = show.episodes.filter {
                $0.seasonNumber == mapped.seasonNumber && $0.episodeNumber == mapped.episodeNumber
            }
            guard let episode = exact ?? (coordinateMatches.count == 1 ? coordinateMatches[0] : nil) else { continue }
            episode.tvdbID = externalID
            if !existingKeys.contains(record.stableKey) {
                let event = WatchEvent(
                    stableKey: record.stableKey,
                    watchedAt: record.watchedAt ?? Date(),
                    source: .tvTimeV2,
                    isEstimatedDate: record.watchedAt == nil,
                    episode: episode
                )
                container.mainContext.insert(event)
                episode.watchEvents.append(event)
                existingKeys.insert(record.stableKey)
            }
            container.mainContext.delete(record)
        }
    }

    private func rescheduleNotifications(shows: [Show]) async {
        let settings = NotificationSettings.current
        let candidates = shows.flatMap { show in
            show.episodes.map { episode in
                NotificationCandidate(
                    identifier: "tbtempo.episode.\(episode.id.uuidString)",
                    title: show.title,
                    body: "\(episode.coordinate) · \(episode.title)",
                    airDate: episode.airDate,
                    isWatched: episode.isWatched,
                    isActive: show.libraryState == .active && !episode.isCanceled,
                    isEnabled: settings.globalEnabled && show.notificationsEnabled
                )
            }
        }
        try? await notificationScheduler.reschedule(candidates: candidates, settings: settings)
    }
}
