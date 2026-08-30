import Foundation
import SwiftData
import ZIPFoundation

struct BackupManifest: Codable, Sendable {
    let format: String
    let schemaVersion: Int
    let createdAt: Date
    let appVersion: String
    let contents: [String]
}

struct BackupPayload: Codable, Sendable {
    let shows: [BackupShow]
    let notificationSettings: NotificationSettings
}

struct BackupShow: Codable, Sendable {
    let id: UUID
    let title: String
    let overview: String
    let status: ShowStatus
    let libraryState: LibraryState
    let genres: [String]
    let tmdbID: Int?
    let tvdbID: Int?
    let posterPath: String?
    let backdropPath: String?
    let defaultRuntimeMinutes: Int?
    let followedAt: Date?
    let lastActivityAt: Date?
    let notificationsEnabled: Bool
    let episodes: [BackupEpisode]
}

struct BackupEpisode: Codable, Sendable {
    let id: UUID
    let seasonNumber: Int
    let episodeNumber: Int
    let title: String
    let overview: String
    let tmdbID: Int?
    let tvdbID: Int?
    let runtimeMinutes: Int?
    let airDate: Date?
    let airDatePrecision: AirDatePrecision
    let stillPath: String?
    let isSpecial: Bool
    let isCanceled: Bool
    let watchEvents: [WatchEventSnapshot]
}

struct BackupPreview: Sendable {
    let manifest: BackupManifest
    let payload: BackupPayload
    var showCount: Int { payload.shows.count }
    var episodeCount: Int { payload.shows.reduce(0) { $0 + $1.episodes.count } }
    var watchCount: Int { payload.shows.flatMap(\.episodes).reduce(0) { $0 + $1.watchEvents.count } }
}

enum BackupImportMode: String, CaseIterable, Identifiable, Sendable {
    case merge
    case replace
    var id: String { rawValue }
    var title: String { self == .merge ? String(localized: "Merge") : String(localized: "Replace") }
}

enum BackupError: LocalizedError {
    case invalidPackage
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .invalidPackage: String(localized: "This is not a valid TB Tempo backup.")
        case .unsupportedVersion(let version): String(localized: "Backup schema version \(version) is not supported by this version of TB Tempo.")
        }
    }
}

enum BackupService {
    static let schemaVersion = 1

    @MainActor
    static func export(shows: [Show], settings: NotificationSettings = .current) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let payload = BackupPayload(shows: shows.map(snapshot), notificationSettings: settings)
        let manifest = BackupManifest(
            format: "com.tbtempo.backup",
            schemaVersion: schemaVersion,
            createdAt: Date(),
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0",
            contents: ["manifest.json", "data.json"]
        )
        let files = ["manifest.json": try encoder.encode(manifest), "data.json": try encoder.encode(payload)]
        let date = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let url = FileManager.default.temporaryDirectory.appending(path: "TBTempo-\(date).tbtempo")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        let archive = try Archive(url: url, accessMode: .create)
        for (path, data) in files {
            try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate) { position, size in
                let start = Int(position)
                return data.subdata(in: start..<min(start + size, data.count))
            }
        }
        return url
    }

    static func preview(url: URL) throws -> BackupPreview {
        let archive = try Archive(url: url, accessMode: .read)
        guard let manifestEntry = archive.first(where: { $0.path == "manifest.json" }),
              let dataEntry = archive.first(where: { $0.path == "data.json" }),
              manifestEntry.uncompressedSize < 1_000_000,
              dataEntry.uncompressedSize < 100_000_000 else { throw BackupError.invalidPackage }
        var manifestData = Data()
        var payloadData = Data()
        _ = try archive.extract(manifestEntry) { manifestData.append($0) }
        _ = try archive.extract(dataEntry) { payloadData.append($0) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(BackupManifest.self, from: manifestData)
        guard manifest.format == "com.tbtempo.backup" else { throw BackupError.invalidPackage }
        guard manifest.schemaVersion == schemaVersion else { throw BackupError.unsupportedVersion(manifest.schemaVersion) }
        let payload = try decoder.decode(BackupPayload.self, from: payloadData)
        let showIDs = payload.shows.map(\.id)
        let episodeIDs = payload.shows.flatMap(\.episodes).map(\.id)
        let eventKeys = payload.shows.flatMap(\.episodes).flatMap(\.watchEvents).map(\.stableKey)
        guard Set(showIDs).count == showIDs.count,
              Set(episodeIDs).count == episodeIDs.count,
              Set(eventKeys).count == eventKeys.count else { throw BackupError.invalidPackage }
        return BackupPreview(manifest: manifest, payload: payload)
    }

    @MainActor
    static func restore(_ preview: BackupPreview, mode: BackupImportMode, context: ModelContext) throws {
        do {
            if mode == .replace {
                try context.delete(model: Show.self)
                try context.delete(model: UnresolvedImportRecord.self)
                try context.delete(model: ImportReceipt.self)
            }
            var existingShowsByID = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<Show>()).map { ($0.id, $0) })
            var existingEvents = Set(try context.fetch(FetchDescriptor<WatchEvent>()).map(\.stableKey))
            for item in preview.payload.shows {
                let show = existingShowsByID[item.id] ?? Show(id: item.id, title: item.title)
                if show.modelContext == nil { context.insert(show); existingShowsByID[item.id] = show }
                show.title = item.title
                show.normalizedTitle = TextNormalizer.title(item.title)
                show.overview = item.overview
                show.status = item.status
                show.libraryState = item.libraryState
                show.genres = item.genres
                show.tmdbID = item.tmdbID
                show.tvdbID = item.tvdbID
                show.posterPath = item.posterPath
                show.backdropPath = item.backdropPath
                show.defaultRuntimeMinutes = item.defaultRuntimeMinutes
                show.followedAt = item.followedAt
                show.lastActivityAt = item.lastActivityAt
                show.notificationsEnabled = item.notificationsEnabled

                var episodeByID = Dictionary(uniqueKeysWithValues: show.episodes.map { ($0.id, $0) })
                for episodeItem in item.episodes {
                    let episode = episodeByID[episodeItem.id] ?? Episode(
                        id: episodeItem.id,
                        seasonNumber: episodeItem.seasonNumber,
                        episodeNumber: episodeItem.episodeNumber,
                        title: episodeItem.title,
                        show: show
                    )
                    if episode.modelContext == nil { context.insert(episode); show.episodes.append(episode); episodeByID[episode.id] = episode }
                    episode.title = episodeItem.title
                    episode.overview = episodeItem.overview
                    episode.tmdbID = episodeItem.tmdbID
                    episode.tvdbID = episodeItem.tvdbID
                    episode.runtimeMinutes = episodeItem.runtimeMinutes
                    episode.airDate = episodeItem.airDate
                    episode.airDatePrecision = episodeItem.airDatePrecision
                    episode.stillPath = episodeItem.stillPath
                    episode.isSpecial = episodeItem.isSpecial
                    episode.isCanceled = episodeItem.isCanceled
                    for eventItem in episodeItem.watchEvents where !existingEvents.contains(eventItem.stableKey) {
                        let event = WatchEvent(stableKey: eventItem.stableKey, watchedAt: eventItem.watchedAt, source: .backup, isEstimatedDate: eventItem.isEstimatedDate, episode: episode)
                        context.insert(event)
                        episode.watchEvents.append(event)
                        existingEvents.insert(eventItem.stableKey)
                    }
                }
            }
            UserDefaults.standard.set(preview.payload.notificationSettings.globalEnabled, forKey: "notificationsEnabled")
            UserDefaults.standard.set(preview.payload.notificationSettings.hour, forKey: "notificationHour")
            UserDefaults.standard.set(preview.payload.notificationSettings.minute, forKey: "notificationMinute")
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    @MainActor
    static func exportViewingHistoryCSV(shows: [Show]) throws -> URL {
        var lines = ["series,season,episode,episode_title,watched_at,runtime_minutes,source"]
        let formatter = ISO8601DateFormatter()
        for show in shows.sorted(by: { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) {
            for episode in show.episodes.sorted(by: Episode.canonicalOrder) {
                for event in episode.watchEvents.sorted(by: { $0.watchedAt < $1.watchedAt }) {
                    let values = [show.title, String(episode.seasonNumber), String(episode.episodeNumber), episode.title, formatter.string(from: event.watchedAt), episode.effectiveRuntime.map(String.init) ?? "", event.source.rawValue]
                    lines.append(values.map(csvEscape).joined(separator: ","))
                }
            }
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "TBTempo-viewing-history.csv")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func snapshot(_ show: Show) -> BackupShow {
        BackupShow(
            id: show.id,
            title: show.title,
            overview: show.overview,
            status: show.status,
            libraryState: show.libraryState,
            genres: show.genres,
            tmdbID: show.tmdbID,
            tvdbID: show.tvdbID,
            posterPath: show.posterPath,
            backdropPath: show.backdropPath,
            defaultRuntimeMinutes: show.defaultRuntimeMinutes,
            followedAt: show.followedAt,
            lastActivityAt: show.lastActivityAt,
            notificationsEnabled: show.notificationsEnabled,
            episodes: show.episodes.map { episode in
                BackupEpisode(
                    id: episode.id,
                    seasonNumber: episode.seasonNumber,
                    episodeNumber: episode.episodeNumber,
                    title: episode.title,
                    overview: episode.overview,
                    tmdbID: episode.tmdbID,
                    tvdbID: episode.tvdbID,
                    runtimeMinutes: episode.runtimeMinutes,
                    airDate: episode.airDate,
                    airDatePrecision: episode.airDatePrecision,
                    stillPath: episode.stillPath,
                    isSpecial: episode.isSpecial,
                    isCanceled: episode.isCanceled,
                    watchEvents: episode.watchEvents.map { WatchEventSnapshot(stableKey: $0.stableKey, watchedAt: $0.watchedAt, source: $0.source, isEstimatedDate: $0.isEstimatedDate) }
                )
            }
        )
    }

    private static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
