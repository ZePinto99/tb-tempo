import CryptoKit
import Foundation
import SwiftData
import ZIPFoundation

struct ImportedSeriesDraft: Identifiable, Hashable, Sendable {
    var id: Int { tvdbID }
    let tvdbID: Int
    let title: String
    let state: LibraryState
    let followedAt: Date?
    let defaultRuntimeMinutes: Int?
}

struct ImportedWatchDraft: Identifiable, Hashable, Sendable {
    var id: String { stableKey }
    let stableKey: String
    let tvdbSeriesID: Int
    let seriesTitle: String
    let tvdbEpisodeID: Int
    let seasonNumber: Int
    let episodeNumber: Int
    let watchedAt: Date
    let runtimeMinutes: Int?
    let isSpecial: Bool
}

struct UnresolvedDraft: Identifiable, Hashable, Sendable {
    var id: String { stableKey }
    let stableKey: String
    let seriesTitle: String
    let tvdbSeriesID: Int?
    let tvdbEpisodeID: Int?
    let seasonNumber: Int?
    let episodeNumber: Int?
    let watchedAt: Date?
    let reason: String
}

struct TVTimeImportPreview: Sendable {
    let fingerprint: String
    let sourceName: String
    let series: [ImportedSeriesDraft]
    let watches: [ImportedWatchDraft]
    let unresolved: [UnresolvedDraft]
    let duplicateCount: Int
    let stoppedCount: Int
    let exportedEpisodeCount: Int?
    let exportedViewingMinutes: Int?
    let calculatedViewingMinutes: Int
    let unknownRuntimeCount: Int
    let relevantFiles: [String]
}

struct TVTimeImportResult: Sendable {
    let insertedSeries: Int
    let insertedWatches: Int
    let skippedExistingWatches: Int
    let unresolved: Int
    let calculatedViewingMinutes: Int
    let exportedViewingMinutes: Int?
}

enum TVTimeImportError: LocalizedError {
    case missingPrimaryFile
    case oversizedEntry(String)
    case alreadyImported
    case invalidArchive

    var errorDescription: String? {
        switch self {
        case .missingPrimaryFile: String(localized: "This ZIP does not contain tracking-prod-records-v2.csv.")
        case .oversizedEntry(let name): String(localized: "The archive entry \(name) is unexpectedly large.")
        case .alreadyImported: String(localized: "This exact TV Time export has already been imported.")
        case .invalidArchive: String(localized: "The selected file is not a valid TV Time ZIP export.")
        }
    }
}

enum TVTimeImporter {
    static let allowlist: Set<String> = [
        "tracking-prod-records-v2.csv",
        "user_tv_show_data.csv",
        "followed_tv_show.csv",
        "followed_tv_show_source.csv",
        "seen_episode_source.csv",
        "show_seen_episode_latest.csv",
        "seen_episode_latest.csv",
        "user_statistics.csv",
        "stats-prod-cache.csv"
    ]

    static func preview(url: URL) throws -> TVTimeImportPreview {
        let archive = try Archive(url: url, accessMode: .read)
        let entries = archive.filter { allowlist.contains(URL(fileURLWithPath: $0.path).lastPathComponent) }
        guard !entries.isEmpty else { throw TVTimeImportError.invalidArchive }
        var files: [String: Data] = [:]
        var totalUncompressedSize: UInt64 = 0
        for entry in entries {
            let name = URL(fileURLWithPath: entry.path).lastPathComponent
            guard entry.uncompressedSize <= 75_000_000 else { throw TVTimeImportError.oversizedEntry(name) }
            totalUncompressedSize += entry.uncompressedSize
            guard totalUncompressedSize <= 150_000_000, files[name] == nil else { throw TVTimeImportError.invalidArchive }
            var data = Data()
            _ = try archive.extract(entry) { data.append($0) }
            files[name] = data
        }
        guard let primary = files["tracking-prod-records-v2.csv"] else { throw TVTimeImportError.missingPrimaryFile }
        let trackingRows = try CSVReader.rows(data: primary)
        let stateRows = trackingRows.filter { ($0["ep_id"] ?? "").isEmpty && !($0["series_name"] ?? "").isEmpty }
        let watchRows = trackingRows.filter { !($0["ep_id"] ?? "").isEmpty }

        let runtimeBySeries = Dictionary(grouping: watchRows.compactMap { row -> (Int, Int)? in
            guard let sid = Int(row["s_id"] ?? ""), let runtime = Int(row["runtime"] ?? ""), runtime > 0 else { return nil }
            return (sid, runtime)
        }, by: \.0).mapValues { values in
            let sorted = values.map(\.1).sorted()
            return sorted[sorted.count / 2]
        }

        var seriesByID: [Int: ImportedSeriesDraft] = [:]
        for row in stateRows {
            guard let id = Int(row["s_id"] ?? ""), id > 0, let title = row["series_name"], !title.isEmpty else { continue }
            let followed = bool(row["is_followed"])
            let archived = bool(row["is_archived"])
            seriesByID[id] = ImportedSeriesDraft(
                tvdbID: id,
                title: title,
                state: (followed && !archived) ? .active : .stopped,
                followedAt: epochMilliseconds(row["followed_at"]),
                defaultRuntimeMinutes: runtimeBySeries[id]
            )
        }
        for row in watchRows {
            guard let id = Int(row["s_id"] ?? ""), id > 0, seriesByID[id] == nil, let title = row["series_name"], !title.isEmpty else { continue }
            seriesByID[id] = ImportedSeriesDraft(tvdbID: id, title: title, state: .active, followedAt: nil, defaultRuntimeMinutes: runtimeBySeries[id])
        }

        let coordinateGroups = Dictionary(grouping: watchRows) { row in
            "\(row["s_id"] ?? ""):\(row["s_no"] ?? row["season_number"] ?? ""):\(row["ep_no"] ?? row["episode_number"] ?? "")"
        }
        let ambiguousCoordinates = Set(coordinateGroups.compactMap { key, values in
            Set(values.compactMap { $0["ep_id"] }).count > 1 ? key : nil
        })

        var watches: [ImportedWatchDraft] = []
        var unresolved: [UnresolvedDraft] = []
        var seenStableKeys = Set<String>()
        var duplicateCount = 0
        for (index, row) in watchRows.enumerated() {
            let rawKey = row["key"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let stableKey = "tvtime:v2:\((rawKey?.isEmpty == false ? rawKey : nil) ?? "row-\(index)")"
            guard seenStableKeys.insert(stableKey).inserted else {
                duplicateCount += 1
                continue
            }
            let sid = Int(row["s_id"] ?? "")
            let eid = Int(row["ep_id"] ?? "")
            let season = Int(row["s_no"] ?? row["season_number"] ?? "")
            let number = Int(row["ep_no"] ?? row["episode_number"] ?? "")
            let coordinate = "\(row["s_id"] ?? ""):\(row["s_no"] ?? row["season_number"] ?? ""):\(row["ep_no"] ?? row["episode_number"] ?? "")"
            let watchedAt = parseDate(row["created_at"]) ?? parseDate(row["updated_at"])
            let title = row["series_name"] ?? String(localized: "Unknown series")
            guard let sid, sid > 0, let eid, eid > 0, let season, let number, let watchedAt else {
                unresolved.append(UnresolvedDraft(stableKey: stableKey, seriesTitle: title, tvdbSeriesID: sid, tvdbEpisodeID: eid, seasonNumber: season, episodeNumber: number, watchedAt: watchedAt, reason: String(localized: "Missing a stable ID, episode coordinate, or watch date")))
                continue
            }
            guard !ambiguousCoordinates.contains(coordinate) else {
                unresolved.append(UnresolvedDraft(stableKey: stableKey, seriesTitle: title, tvdbSeriesID: sid, tvdbEpisodeID: eid, seasonNumber: season, episodeNumber: number, watchedAt: watchedAt, reason: String(localized: "Multiple external episode IDs share this coordinate")))
                continue
            }
            watches.append(ImportedWatchDraft(
                stableKey: stableKey,
                tvdbSeriesID: sid,
                seriesTitle: title,
                tvdbEpisodeID: eid,
                seasonNumber: season,
                episodeNumber: number,
                watchedAt: watchedAt,
                runtimeMinutes: Int(row["runtime"] ?? ""),
                isSpecial: bool(row["is_special"]) || season == 0
            ))
        }

        var exportedEpisodeCount: Int?
        var exportedViewingMinutes: Int?
        if let statsData = files["user_statistics.csv"], let row = try CSVReader.rows(data: statsData).first {
            exportedEpisodeCount = Int(row["nb_episodes_watched"] ?? "")
            if let value = Int(row["time_spent"] ?? "") { exportedViewingMinutes = value }
        }
        if let aggregateRow = trackingRows.first(where: { !($0["total_series_runtime"] ?? "").isEmpty }),
           let seconds = Int(aggregateRow["total_series_runtime"] ?? "") {
            exportedViewingMinutes = seconds / 60
        }
        if let count = stateRows.compactMap({ Int($0["ep_watch_count"] ?? "") }).reduce(nil, { current, value in (current ?? 0) + value }) {
            exportedEpisodeCount = count
        }

        let calculatedMinutes = watches.reduce(0) { total, watch in
            total + (watch.runtimeMinutes ?? runtimeBySeries[watch.tvdbSeriesID] ?? 0)
        }
        let unknownRuntimeCount = watches.filter { $0.runtimeMinutes == nil && runtimeBySeries[$0.tvdbSeriesID] == nil }.count
        let fingerprint = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
        return TVTimeImportPreview(
            fingerprint: fingerprint,
            sourceName: url.lastPathComponent,
            series: seriesByID.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending },
            watches: watches,
            unresolved: unresolved,
            duplicateCount: duplicateCount,
            stoppedCount: seriesByID.values.filter { $0.state == .stopped }.count,
            exportedEpisodeCount: exportedEpisodeCount,
            exportedViewingMinutes: exportedViewingMinutes,
            calculatedViewingMinutes: calculatedMinutes,
            unknownRuntimeCount: unknownRuntimeCount,
            relevantFiles: files.keys.sorted()
        )
    }

    @MainActor
    static func commit(_ preview: TVTimeImportPreview, to context: ModelContext) throws -> TVTimeImportResult {
        let receiptFingerprint = preview.fingerprint
        var receiptDescriptor = FetchDescriptor<ImportReceipt>(predicate: #Predicate { $0.fingerprint == receiptFingerprint })
        receiptDescriptor.fetchLimit = 1
        guard try context.fetch(receiptDescriptor).isEmpty else { throw TVTimeImportError.alreadyImported }

        let existingShows = try context.fetch(FetchDescriptor<Show>())
        var showsByTVDB: [Int: Show] = [:]
        for show in existingShows { if let tvdbID = show.tvdbID { showsByTVDB[tvdbID] = show } }
        let existingEvents = Set(try context.fetch(FetchDescriptor<WatchEvent>()).map(\.stableKey))
        let existingUnresolved = Set(try context.fetch(FetchDescriptor<UnresolvedImportRecord>()).map(\.stableKey))
        var insertedSeries = 0
        var insertedWatches = 0
        var skipped = 0

        do {
            for draft in preview.series {
                if let show = showsByTVDB[draft.tvdbID] {
                    if show.defaultRuntimeMinutes == nil { show.defaultRuntimeMinutes = draft.defaultRuntimeMinutes }
                    if show.followedAt == nil { show.followedAt = draft.followedAt }
                    if show.libraryState == .active, draft.state == .stopped { show.libraryState = .stopped }
                } else {
                    let show = Show(
                        title: draft.title,
                        libraryState: draft.state,
                        tvdbID: draft.tvdbID,
                        defaultRuntimeMinutes: draft.defaultRuntimeMinutes,
                        followedAt: draft.followedAt,
                        importedArchived: draft.state == .stopped
                    )
                    context.insert(show)
                    showsByTVDB[draft.tvdbID] = show
                    insertedSeries += 1
                }
            }

            for draft in preview.watches {
                guard !existingEvents.contains(draft.stableKey) else { skipped += 1; continue }
                guard let show = showsByTVDB[draft.tvdbSeriesID] else { continue }
                let episode = show.episodes.first { $0.tvdbID == draft.tvdbEpisodeID }
                    ?? show.episodes.first { $0.seasonNumber == draft.seasonNumber && $0.episodeNumber == draft.episodeNumber }
                    ?? Episode(
                        seasonNumber: draft.seasonNumber,
                        episodeNumber: draft.episodeNumber,
                        title: String(localized: "Episode \(draft.episodeNumber)"),
                        tvdbID: draft.tvdbEpisodeID,
                        runtimeMinutes: draft.runtimeMinutes,
                        isSpecial: draft.isSpecial,
                        show: show
                    )
                if episode.modelContext == nil {
                    context.insert(episode)
                    show.episodes.append(episode)
                }
                episode.tvdbID = episode.tvdbID ?? draft.tvdbEpisodeID
                episode.runtimeMinutes = episode.runtimeMinutes ?? draft.runtimeMinutes
                let event = WatchEvent(stableKey: draft.stableKey, watchedAt: draft.watchedAt, source: .tvTimeV2, episode: episode)
                context.insert(event)
                episode.watchEvents.append(event)
                if show.lastActivityAt == nil || draft.watchedAt > show.lastActivityAt! { show.lastActivityAt = draft.watchedAt }
                insertedWatches += 1
            }

            for draft in preview.unresolved where !existingUnresolved.contains(draft.stableKey) {
                context.insert(UnresolvedImportRecord(
                    stableKey: draft.stableKey,
                    seriesTitle: draft.seriesTitle,
                    tvdbSeriesID: draft.tvdbSeriesID,
                    tvdbEpisodeID: draft.tvdbEpisodeID,
                    seasonNumber: draft.seasonNumber,
                    episodeNumber: draft.episodeNumber,
                    watchedAt: draft.watchedAt,
                    reason: draft.reason
                ))
            }

            context.insert(ImportReceipt(
                fingerprint: preview.fingerprint,
                sourceName: preview.sourceName,
                seriesCount: preview.series.count,
                watchCount: insertedWatches,
                unresolvedCount: preview.unresolved.count,
                duplicateCount: preview.duplicateCount,
                exportedEpisodeCount: preview.exportedEpisodeCount,
                calculatedEpisodeCount: preview.watches.count,
                exportedViewingMinutes: preview.exportedViewingMinutes,
                calculatedViewingMinutes: preview.calculatedViewingMinutes
            ))
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return TVTimeImportResult(
            insertedSeries: insertedSeries,
            insertedWatches: insertedWatches,
            skippedExistingWatches: skipped,
            unresolved: preview.unresolved.count,
            calculatedViewingMinutes: preview.calculatedViewingMinutes,
            exportedViewingMinutes: preview.exportedViewingMinutes
        )
    }

    private static func bool(_ value: String?) -> Bool {
        guard let value else { return false }
        return ["1", "true", "yes"].contains(value.lowercased())
    }

    private static func epochMilliseconds(_ value: String?) -> Date? {
        guard let value, let number = Double(value), number > 0 else { return nil }
        return Date(timeIntervalSince1970: number > 10_000_000_000 ? number / 1_000 : number)
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) { return date }
        return epochMilliseconds(value)
    }
}
