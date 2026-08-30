import Foundation
import SwiftData
import Testing
@testable import TBTempo

struct TBTempoTests {
    @Test func CSVHandlesQuotedCommasAndNewlines() throws {
        let data = Data("name,note\n\"Tempo, House\",\"line one\nline two\"\n".utf8)
        let rows = try CSVReader.rows(data: data)
        #expect(rows.count == 1)
        #expect(rows[0]["name"] == "Tempo, House")
        #expect(rows[0]["note"] == "line one\nline two")
    }

    @Test func countdownUsesLocalCalendarDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Lisbon")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 23, minute: 45))!
        let tomorrow = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1, hour: 0, minute: 5))!
        #expect(CountdownFormatter.daysRemaining(until: tomorrow, from: now, calendar: calendar) == 1)
        #expect(CountdownFormatter.text(until: tomorrow, from: now, calendar: calendar) == "tomorrow")
        #expect(CountdownFormatter.text(until: nil, from: now, calendar: calendar) == "date not confirmed")
    }

    @Test func notificationPlannerFiltersAndLimits() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 31, hour: 8))!
        let today = calendar.startOfDay(for: now)
        let candidates = [
            NotificationCandidate(identifier: "one", title: "A", body: "E1", airDate: today, isWatched: false, isActive: true, isEnabled: true),
            NotificationCandidate(identifier: "two", title: "B", body: "E2", airDate: calendar.date(byAdding: .day, value: 3, to: today), isWatched: false, isActive: true, isEnabled: true),
            NotificationCandidate(identifier: "watched", title: "C", body: "E3", airDate: today, isWatched: true, isActive: true, isEnabled: true),
            NotificationCandidate(identifier: "late", title: "D", body: "E4", airDate: calendar.date(byAdding: .day, value: 91, to: today), isWatched: false, isActive: true, isEnabled: true)
        ]
        let settings = NotificationSettings(globalEnabled: true, hour: 9, minute: 0, horizonDays: 90, rollingLimit: 1)
        let plan = NotificationPlanner.plan(candidates: candidates, settings: settings, now: now, calendar: calendar)
        #expect(plan.map(\.identifier) == ["one"])
        #expect(calendar.component(.hour, from: plan[0].date) == 9)
    }

    @MainActor
    @Test func progressUndoRestoresEveryWatchEvent() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let show = Show(title: "Tempo House")
        let episode = Episode(seasonNumber: 1, episodeNumber: 1, title: "Pilot", runtimeMinutes: 42, show: show)
        context.insert(show); context.insert(episode); show.episodes.append(episode)
        try context.save()
        let controller = ProgressController()
        controller.toggle(episode, in: context)
        #expect(episode.isWatched)
        #expect(episode.watchEvents.count == 1)
        controller.undo(in: context)
        #expect(!episode.isWatched)
        #expect(episode.watchEvents.isEmpty)
    }

    @MainActor
    @Test func seasonProgressKeepsSpecialsSeparateAndStatisticsCountRewatches() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let show = Show(title: "Tempo House", defaultRuntimeMinutes: 40)
        let regular = Episode(seasonNumber: 1, episodeNumber: 1, title: "Pilot", runtimeMinutes: 42, show: show)
        let special = Episode(seasonNumber: 0, episodeNumber: 1, title: "Bonus", runtimeMinutes: 20, isSpecial: true, show: show)
        context.insert(show); context.insert(regular); context.insert(special)
        show.episodes.append(contentsOf: [regular, special])
        let first = WatchEvent(stableKey: "manual:one", watchedAt: Date(), source: .manual, episode: regular)
        let second = WatchEvent(stableKey: "manual:two", watchedAt: Date(), source: .manual, episode: regular)
        context.insert(first); context.insert(second); regular.watchEvents.append(contentsOf: [first, second])
        try context.save()
        #expect(show.progress == 1)
        #expect(show.watchedRegularEpisodes.count == 1)
        let report = StatisticsEngine.report(shows: [show])
        #expect(report.watchedEpisodeCount == 1)
        #expect(report.watchEventCount == 2)
        #expect(report.totalMinutes == 84)
    }

    @MainActor
    @Test func backupRoundTripKeepsStableHistoryAndPreferences() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let show = Show(title: "Quiet Orbit", tmdbID: 55, tvdbID: 66)
        let episode = Episode(seasonNumber: 2, episodeNumber: 3, title: "Signal", runtimeMinutes: 51, show: show)
        let event = WatchEvent(stableKey: "fixture:watch", watchedAt: Date(timeIntervalSince1970: 1_700_000_000), source: .manual, episode: episode)
        context.insert(show); context.insert(episode); context.insert(event)
        show.episodes.append(episode); episode.watchEvents.append(event)
        try context.save()
        let settings = NotificationSettings(globalEnabled: true, hour: 8, minute: 30, horizonDays: 90, rollingLimit: 50)
        let url = try BackupService.export(shows: [show], settings: settings)
        let preview = try BackupService.preview(url: url)
        #expect(preview.showCount == 1)
        #expect(preview.episodeCount == 1)
        #expect(preview.watchCount == 1)
        #expect(preview.payload.notificationSettings.hour == 8)
        #expect(preview.payload.shows[0].episodes[0].watchEvents[0].stableKey == "fixture:watch")
        try BackupService.restore(preview, mode: .merge, context: context)
        try BackupService.restore(preview, mode: .merge, context: context)
        #expect(try context.fetch(FetchDescriptor<WatchEvent>()).count == 1)
    }

    @MainActor
    @Test func sanitizedTVTimeImportReportsAmbiguityAndIsIdempotent() throws {
        let fixture = try #require(Bundle(for: TestBundleMarker.self).url(forResource: "gdpr-sanitized", withExtension: "zip"))
        let preview = try TVTimeImporter.preview(url: fixture)
        #expect(preview.series.count == 2)
        #expect(preview.watches.count == 2)
        #expect(preview.unresolved.count == 2)
        #expect(preview.duplicateCount == 1)
        let container = try makeContainer()
        let result = try TVTimeImporter.commit(preview, to: container.mainContext)
        #expect(result.insertedSeries == 2)
        #expect(result.insertedWatches == 2)
        #expect(throws: TVTimeImportError.self) {
            try TVTimeImporter.commit(preview, to: container.mainContext)
        }
    }

    @MainActor
    @Test func failedZeroWatchImportCanBeRepaired() throws {
        let fixture = try #require(Bundle(for: TestBundleMarker.self).url(forResource: "gdpr-sanitized", withExtension: "zip"))
        let preview = try TVTimeImporter.preview(url: fixture)
        let container = try makeContainer()
        let context = container.mainContext

        var showsByTVDB: [Int: Show] = [:]
        for draft in preview.series {
            let show = Show(title: draft.title, tvdbID: draft.tvdbID)
            context.insert(show)
            showsByTVDB[draft.tvdbID] = show
        }
        for watch in preview.watches {
            context.insert(UnresolvedImportRecord(
                stableKey: watch.stableKey,
                seriesTitle: watch.seriesTitle,
                tvdbSeriesID: watch.tvdbSeriesID,
                tvdbEpisodeID: watch.tvdbEpisodeID,
                seasonNumber: watch.seasonNumber,
                episodeNumber: watch.episodeNumber,
                watchedAt: nil,
                reason: "Old timestamp failure"
            ))
        }

        let repairedDraft = try #require(preview.watches.first)
        let repairedShow = try #require(showsByTVDB[repairedDraft.tvdbSeriesID])
        let repairedEpisode = Episode(
            seasonNumber: repairedDraft.seasonNumber,
            episodeNumber: repairedDraft.episodeNumber,
            title: "Old episode",
            tvdbID: repairedDraft.tvdbEpisodeID,
            show: repairedShow
        )
        context.insert(repairedEpisode)
        repairedShow.episodes.append(repairedEpisode)
        let repairedEvent = WatchEvent(
            stableKey: repairedDraft.stableKey,
            watchedAt: Date(timeIntervalSince1970: 1),
            source: .tvTimeV2,
            episode: repairedEpisode
        )
        context.insert(repairedEvent)
        repairedEpisode.watchEvents.append(repairedEvent)

        let unresolvedDraft = try #require(preview.unresolved.first)
        let unresolvedSeriesID = try #require(unresolvedDraft.tvdbSeriesID)
        let unresolvedShow = try #require(showsByTVDB[unresolvedSeriesID])
        let incorrectEpisode = Episode(
            seasonNumber: try #require(unresolvedDraft.seasonNumber),
            episodeNumber: try #require(unresolvedDraft.episodeNumber),
            title: "Incorrectly resolved episode",
            tvdbID: unresolvedDraft.tvdbEpisodeID,
            show: unresolvedShow
        )
        context.insert(incorrectEpisode)
        unresolvedShow.episodes.append(incorrectEpisode)
        let incorrectEvent = WatchEvent(
            stableKey: unresolvedDraft.stableKey,
            watchedAt: Date(timeIntervalSince1970: 1),
            source: .tvTimeV2,
            episode: incorrectEpisode
        )
        context.insert(incorrectEvent)
        incorrectEpisode.watchEvents.append(incorrectEvent)

        context.insert(ImportReceipt(
            fingerprint: preview.fingerprint,
            sourceName: preview.sourceName,
            seriesCount: preview.series.count,
            watchCount: 0,
            unresolvedCount: preview.watches.count,
            duplicateCount: preview.duplicateCount,
            exportedEpisodeCount: preview.exportedEpisodeCount,
            calculatedEpisodeCount: 0,
            exportedViewingMinutes: preview.exportedViewingMinutes,
            calculatedViewingMinutes: 0
        ))
        try context.save()

        let result = try TVTimeImporter.commit(preview, to: context)
        #expect(result.insertedWatches == 1)
        let events = try context.fetch(FetchDescriptor<WatchEvent>())
        #expect(events.count == 2)
        #expect(events.first { $0.stableKey == repairedDraft.stableKey }?.watchedAt == repairedDraft.watchedAt)
        #expect(events.allSatisfy { $0.stableKey != unresolvedDraft.stableKey })
        #expect(try context.fetch(FetchDescriptor<UnresolvedImportRecord>()).count == preview.unresolved.count)
        let receipts = try context.fetch(FetchDescriptor<ImportReceipt>())
        #expect(receipts.count == 1)
        #expect(receipts.first?.watchCount == 2)
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Show.self, Episode.self, WatchEvent.self, ImportReceipt.self, UnresolvedImportRecord.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration("Tests", schema: schema, isStoredInMemoryOnly: true)])
    }
}

private final class TestBundleMarker {}
