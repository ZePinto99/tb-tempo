import Foundation

struct CatalogSearchResult: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let title: String
    let overview: String
    let firstAirDate: Date?
    let posterPath: String?
}

struct CatalogShow: Codable, Sendable {
    let tmdbID: Int
    let tvdbID: Int?
    let title: String
    let overview: String
    let status: ShowStatus
    let genres: [String]
    let posterPath: String?
    let backdropPath: String?
    let defaultRuntimeMinutes: Int?
    let episodes: [CatalogEpisode]
}

struct CatalogEpisode: Codable, Hashable, Sendable {
    let tmdbID: Int
    let tvdbID: Int?
    let seasonNumber: Int
    let episodeNumber: Int
    let title: String
    let overview: String
    let runtimeMinutes: Int?
    let airDate: Date?
    let airDatePrecision: AirDatePrecision
    let stillPath: String?
}

struct WatchEventSnapshot: Codable, Hashable, Sendable {
    let stableKey: String
    let watchedAt: Date
    let source: WatchSource
    let isEstimatedDate: Bool
}

struct SeriesStatistics: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let eventCount: Int
    let minutes: Int
}

struct LabeledStatistics: Identifiable, Hashable, Sendable {
    var id: String { label }
    let label: String
    let eventCount: Int
    let minutes: Int
}

struct StatisticsReport: Sendable {
    let watchedEpisodeCount: Int
    let watchEventCount: Int
    let totalMinutes: Int
    let unknownRuntimeEventCount: Int
    let bySeries: [SeriesStatistics]
    let bySeason: [LabeledStatistics]
    let byMonth: [LabeledStatistics]
    let byYear: [LabeledStatistics]
}
