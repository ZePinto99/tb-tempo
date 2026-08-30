import Foundation
import SwiftData

enum LibraryState: String, Codable, CaseIterable, Identifiable, Sendable {
    case active
    case stopped
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: String(localized: "Active")
        case .stopped: String(localized: "Stopped")
        case .completed: String(localized: "Completed")
        }
    }
}

enum ShowStatus: String, Codable, Sendable {
    case returning = "Returning Series"
    case ended = "Ended"
    case canceled = "Canceled"
    case planned = "Planned"
    case production = "In Production"
    case pilot = "Pilot"
    case unknown = "Unknown"
}

enum AirDatePrecision: String, Codable, Sendable {
    case dateOnly
    case dateTime
    case unknown
}

enum WatchSource: String, Codable, Sendable {
    case manual
    case tvTimeV2
    case tvTimeLegacy
    case backup
}

@Model
final class Show {
    @Attribute(.unique) var id: UUID
    var title: String
    var normalizedTitle: String
    var overview: String
    var statusRaw: String
    var libraryStateRaw: String
    var genresStorage: String
    var tmdbID: Int?
    var tvdbID: Int?
    var posterPath: String?
    var backdropPath: String?
    @Attribute(.externalStorage) var posterData: Data?
    @Attribute(.externalStorage) var backdropData: Data?
    var defaultRuntimeMinutes: Int?
    var followedAt: Date?
    var lastActivityAt: Date?
    var lastMetadataRefresh: Date?
    var notificationsEnabled: Bool
    var importedArchived: Bool
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Episode.show)
    var episodes: [Episode]

    init(
        id: UUID = UUID(),
        title: String,
        overview: String = "",
        status: ShowStatus = .unknown,
        libraryState: LibraryState = .active,
        genres: [String] = [],
        tmdbID: Int? = nil,
        tvdbID: Int? = nil,
        posterPath: String? = nil,
        backdropPath: String? = nil,
        defaultRuntimeMinutes: Int? = nil,
        followedAt: Date? = nil,
        notificationsEnabled: Bool = true,
        importedArchived: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        normalizedTitle = TextNormalizer.title(title)
        self.overview = overview
        statusRaw = status.rawValue
        libraryStateRaw = libraryState.rawValue
        genresStorage = genres.joined(separator: "\u{1F}")
        self.tmdbID = tmdbID
        self.tvdbID = tvdbID
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.defaultRuntimeMinutes = defaultRuntimeMinutes
        self.followedAt = followedAt
        self.notificationsEnabled = notificationsEnabled
        self.importedArchived = importedArchived
        self.createdAt = createdAt
        episodes = []
    }

    var status: ShowStatus {
        get { ShowStatus(rawValue: statusRaw) ?? .unknown }
        set { statusRaw = newValue.rawValue }
    }

    var libraryState: LibraryState {
        get { LibraryState(rawValue: libraryStateRaw) ?? .active }
        set { libraryStateRaw = newValue.rawValue }
    }

    var genres: [String] {
        get { genresStorage.isEmpty ? [] : genresStorage.components(separatedBy: "\u{1F}") }
        set { genresStorage = newValue.joined(separator: "\u{1F}") }
    }

    var regularEpisodes: [Episode] { episodes.filter { !$0.isSpecial } }
    var watchedRegularEpisodes: [Episode] { regularEpisodes.filter(\.isWatched) }
    var progress: Double {
        guard !regularEpisodes.isEmpty else { return 0 }
        return Double(watchedRegularEpisodes.count) / Double(regularEpisodes.count)
    }

    var nextUp: Episode? {
        regularEpisodes
            .filter { !$0.isWatched }
            .sorted(by: Episode.canonicalOrder)
            .first
    }

    var nextRelease: Date? {
        episodes.compactMap(\.airDate).filter { $0 >= Calendar.autoupdatingCurrent.startOfDay(for: Date()) }.min()
    }
}

@Model
final class Episode {
    @Attribute(.unique) var id: UUID
    var seasonNumber: Int
    var episodeNumber: Int
    var title: String
    var overview: String
    var tmdbID: Int?
    var tvdbID: Int?
    var runtimeMinutes: Int?
    var airDate: Date?
    var airDatePrecisionRaw: String
    var stillPath: String?
    @Attribute(.externalStorage) var stillData: Data?
    var isSpecial: Bool
    var isCanceled: Bool
    var show: Show?

    @Relationship(deleteRule: .cascade, inverse: \WatchEvent.episode)
    var watchEvents: [WatchEvent]

    init(
        id: UUID = UUID(),
        seasonNumber: Int,
        episodeNumber: Int,
        title: String,
        overview: String = "",
        tmdbID: Int? = nil,
        tvdbID: Int? = nil,
        runtimeMinutes: Int? = nil,
        airDate: Date? = nil,
        airDatePrecision: AirDatePrecision = .unknown,
        stillPath: String? = nil,
        isSpecial: Bool = false,
        isCanceled: Bool = false,
        show: Show? = nil
    ) {
        self.id = id
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.title = title
        self.overview = overview
        self.tmdbID = tmdbID
        self.tvdbID = tvdbID
        self.runtimeMinutes = runtimeMinutes
        self.airDate = airDate
        airDatePrecisionRaw = airDatePrecision.rawValue
        self.stillPath = stillPath
        self.isSpecial = isSpecial
        self.isCanceled = isCanceled
        self.show = show
        watchEvents = []
    }

    var airDatePrecision: AirDatePrecision {
        get { AirDatePrecision(rawValue: airDatePrecisionRaw) ?? .unknown }
        set { airDatePrecisionRaw = newValue.rawValue }
    }

    var isWatched: Bool { !watchEvents.isEmpty }
    var coordinate: String { "S\(seasonNumber.formatted(.number.precision(.integerLength(2))))E\(episodeNumber.formatted(.number.precision(.integerLength(2))))" }
    var effectiveRuntime: Int? { runtimeMinutes ?? show?.defaultRuntimeMinutes }

    static func canonicalOrder(_ lhs: Episode, _ rhs: Episode) -> Bool {
        if lhs.seasonNumber != rhs.seasonNumber { return lhs.seasonNumber < rhs.seasonNumber }
        return lhs.episodeNumber < rhs.episodeNumber
    }
}

@Model
final class WatchEvent {
    @Attribute(.unique) var stableKey: String
    var watchedAt: Date
    var sourceRaw: String
    var isEstimatedDate: Bool
    var episode: Episode?

    init(
        stableKey: String,
        watchedAt: Date,
        source: WatchSource,
        isEstimatedDate: Bool = false,
        episode: Episode? = nil
    ) {
        self.stableKey = stableKey
        self.watchedAt = watchedAt
        sourceRaw = source.rawValue
        self.isEstimatedDate = isEstimatedDate
        self.episode = episode
    }

    var source: WatchSource {
        get { WatchSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}

@Model
final class ImportReceipt {
    @Attribute(.unique) var fingerprint: String
    var importedAt: Date
    var sourceName: String
    var seriesCount: Int
    var watchCount: Int
    var unresolvedCount: Int
    var duplicateCount: Int
    var exportedEpisodeCount: Int?
    var calculatedEpisodeCount: Int
    var exportedViewingMinutes: Int?
    var calculatedViewingMinutes: Int

    init(
        fingerprint: String,
        importedAt: Date = Date(),
        sourceName: String,
        seriesCount: Int,
        watchCount: Int,
        unresolvedCount: Int,
        duplicateCount: Int,
        exportedEpisodeCount: Int?,
        calculatedEpisodeCount: Int,
        exportedViewingMinutes: Int?,
        calculatedViewingMinutes: Int
    ) {
        self.fingerprint = fingerprint
        self.importedAt = importedAt
        self.sourceName = sourceName
        self.seriesCount = seriesCount
        self.watchCount = watchCount
        self.unresolvedCount = unresolvedCount
        self.duplicateCount = duplicateCount
        self.exportedEpisodeCount = exportedEpisodeCount
        self.calculatedEpisodeCount = calculatedEpisodeCount
        self.exportedViewingMinutes = exportedViewingMinutes
        self.calculatedViewingMinutes = calculatedViewingMinutes
    }
}

@Model
final class UnresolvedImportRecord {
    @Attribute(.unique) var stableKey: String
    var seriesTitle: String
    var tvdbSeriesID: Int?
    var tvdbEpisodeID: Int?
    var seasonNumber: Int?
    var episodeNumber: Int?
    var watchedAt: Date?
    var reason: String
    var createdAt: Date

    init(
        stableKey: String,
        seriesTitle: String,
        tvdbSeriesID: Int?,
        tvdbEpisodeID: Int?,
        seasonNumber: Int?,
        episodeNumber: Int?,
        watchedAt: Date?,
        reason: String
    ) {
        self.stableKey = stableKey
        self.seriesTitle = seriesTitle
        self.tvdbSeriesID = tvdbSeriesID
        self.tvdbEpisodeID = tvdbEpisodeID
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.watchedAt = watchedAt
        self.reason = reason
        createdAt = Date()
    }
}

enum TextNormalizer {
    static func title(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
