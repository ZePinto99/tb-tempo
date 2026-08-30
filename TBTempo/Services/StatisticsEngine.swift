import Foundation

enum StatisticsEngine {
    static func report(shows: [Show], calendar: Calendar = .autoupdatingCurrent) -> StatisticsReport {
        let episodes = shows.flatMap(\.episodes)
        let events = episodes.flatMap { episode in episode.watchEvents.map { (episode, $0) } }
        let uniqueEpisodes = Set(events.map { $0.0.id }).count
        let unknown = events.filter { $0.0.effectiveRuntime == nil }.count
        let total = events.reduce(0) { $0 + ($1.0.effectiveRuntime ?? 0) }

        let bySeries = shows.compactMap { show -> SeriesStatistics? in
            let pairs = show.episodes.flatMap { episode in episode.watchEvents.map { (episode, $0) } }
            guard !pairs.isEmpty else { return nil }
            return SeriesStatistics(
                id: show.id,
                title: show.title,
                eventCount: pairs.count,
                minutes: pairs.reduce(0) { $0 + ($1.0.effectiveRuntime ?? 0) }
            )
        }.sorted { $0.minutes > $1.minutes }

        let bySeasonDictionary = Dictionary(grouping: events) { pair in
            "\(pair.0.show?.title ?? String(localized: "Unknown series")) · S\(pair.0.seasonNumber)"
        }
        let bySeason = grouped(bySeasonDictionary)

        let monthFormatter = DateFormatter()
        monthFormatter.calendar = calendar
        monthFormatter.locale = .autoupdatingCurrent
        monthFormatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        let byMonthDictionary = Dictionary(grouping: events) { monthFormatter.string(from: $0.1.watchedAt) }
        let byMonth = grouped(byMonthDictionary)

        let yearFormatter = DateFormatter()
        yearFormatter.calendar = calendar
        yearFormatter.locale = .autoupdatingCurrent
        yearFormatter.setLocalizedDateFormatFromTemplate("yyyy")
        let byYearDictionary = Dictionary(grouping: events) { yearFormatter.string(from: $0.1.watchedAt) }
        let byYear = grouped(byYearDictionary)

        return StatisticsReport(
            watchedEpisodeCount: uniqueEpisodes,
            watchEventCount: events.count,
            totalMinutes: total,
            unknownRuntimeEventCount: unknown,
            bySeries: bySeries,
            bySeason: bySeason,
            byMonth: byMonth,
            byYear: byYear
        )
    }

    static func duration(_ minutes: Int) -> String {
        let days = minutes / (24 * 60)
        let hours = (minutes % (24 * 60)) / 60
        let remainder = minutes % 60
        var pieces: [String] = []
        if days > 0 { pieces.append(String(localized: "\(days) days")) }
        if hours > 0 { pieces.append(String(localized: "\(hours) hours")) }
        pieces.append(String(localized: "\(remainder) min"))
        return pieces.joined(separator: " ")
    }

    private static func grouped(_ dictionary: [String: [(Episode, WatchEvent)]]) -> [LabeledStatistics] {
        dictionary.map { label, pairs in
            LabeledStatistics(
                label: label,
                eventCount: pairs.count,
                minutes: pairs.reduce(0) { $0 + ($1.0.effectiveRuntime ?? 0) }
            )
        }.sorted { $0.label.localizedStandardCompare($1.label) == .orderedDescending }
    }
}
