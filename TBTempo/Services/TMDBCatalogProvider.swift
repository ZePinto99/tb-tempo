import Foundation

actor TMDBCatalogProvider: CatalogProviding {
    private let configuration: CatalogConfiguration
    private let session: URLSession
    private let decoder: JSONDecoder
    private let calendar: Calendar

    init(configuration: CatalogConfiguration = .bundled(), session: URLSession = .shared, calendar: Calendar = .autoupdatingCurrent) {
        self.configuration = configuration
        self.session = session
        self.calendar = calendar
        decoder = JSONDecoder()
    }

    func search(query: String) async throws -> [CatalogSearchResult] {
        var components = URLComponents(string: "https://api.themoviedb.org/3/search/tv")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: "false"),
            URLQueryItem(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en-US")
        ]
        let response: SearchResponse = try await request(components.url!)
        return response.results.map {
            CatalogSearchResult(
                id: $0.id,
                title: $0.name,
                overview: $0.overview,
                firstAirDate: parseDate($0.firstAirDate),
                posterPath: $0.posterPath
            )
        }
    }

    func lookupTVDBSeries(id: Int) async throws -> CatalogSearchResult? {
        var components = URLComponents(string: "https://api.themoviedb.org/3/find/\(id)")!
        components.queryItems = [URLQueryItem(name: "external_source", value: "tvdb_id")]
        let response: FindResponse = try await request(components.url!)
        guard response.tvResults.count == 1, let item = response.tvResults.first else { return nil }
        return CatalogSearchResult(
            id: item.id,
            title: item.name,
            overview: item.overview,
            firstAirDate: parseDate(item.firstAirDate),
            posterPath: item.posterPath
        )
    }

    func lookupTVDBEpisode(id: Int) async throws -> CatalogEpisode? {
        var components = URLComponents(string: "https://api.themoviedb.org/3/find/\(id)")!
        components.queryItems = [URLQueryItem(name: "external_source", value: "tvdb_id")]
        let response: FindResponse = try await request(components.url!)
        guard response.episodeResults.count == 1, let item = response.episodeResults.first else { return nil }
        return CatalogEpisode(
            tmdbID: item.id,
            tvdbID: id,
            seasonNumber: item.seasonNumber,
            episodeNumber: item.episodeNumber,
            title: item.name,
            overview: item.overview,
            runtimeMinutes: nil,
            airDate: parseDate(item.airDate),
            airDatePrecision: item.airDate == nil ? .unknown : .dateOnly,
            stillPath: item.stillPath
        )
    }

    func show(tmdbID: Int) async throws -> CatalogShow {
        var components = URLComponents(string: "https://api.themoviedb.org/3/tv/\(tmdbID)")!
        components.queryItems = [
            URLQueryItem(name: "append_to_response", value: "external_ids"),
            URLQueryItem(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en-US")
        ]
        let detail: ShowResponse = try await request(components.url!)
        var episodes: [CatalogEpisode] = []
        for season in detail.seasons where season.seasonNumber >= 0 {
            let response: SeasonResponse = try await request(
                URL(string: "https://api.themoviedb.org/3/tv/\(tmdbID)/season/\(season.seasonNumber)")!
            )
            episodes.append(contentsOf: response.episodes.map {
                CatalogEpisode(
                    tmdbID: $0.id,
                    tvdbID: nil,
                    seasonNumber: $0.seasonNumber,
                    episodeNumber: $0.episodeNumber,
                    title: $0.name,
                    overview: $0.overview,
                    runtimeMinutes: $0.runtime,
                    airDate: parseDate($0.airDate),
                    airDatePrecision: $0.airDate == nil ? .unknown : .dateOnly,
                    stillPath: $0.stillPath
                )
            })
        }
        let runtime = detail.episodeRunTime.first
        return CatalogShow(
            tmdbID: detail.id,
            tvdbID: detail.externalIDs?.tvdbID,
            title: detail.name,
            overview: detail.overview,
            status: ShowStatus(rawValue: detail.status) ?? .unknown,
            genres: detail.genres.map(\.name),
            posterPath: detail.posterPath,
            backdropPath: detail.backdropPath,
            defaultRuntimeMinutes: runtime,
            episodes: episodes
        )
    }

    func imageData(path: String, width: Int) async throws -> Data {
        let bucket: String
        switch width {
        case ..<300: bucket = "w300"
        case ..<500: bucket = "w500"
        case ..<780: bucket = "w780"
        default: bucket = "original"
        }
        let url = URL(string: "https://image.tmdb.org/t/p/\(bucket)\(path)")!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw CatalogError.invalidResponse
        }
        return data
    }

    private func request<Response: Decodable>(_ url: URL) async throws -> Response {
        guard configuration.isConfigured else { throw CatalogError.missingToken }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CatalogError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if let payload = try? decoder.decode(ErrorResponse.self, from: data) {
                throw CatalogError.providerMessage(payload.statusMessage)
            }
            throw CatalogError.invalidResponse
        }
        return try decoder.decode(Response.self, from: data)
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        var components = DateComponents()
        let values = value.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return nil }
        components.year = values[0]
        components.month = values[1]
        components.day = values[2]
        components.hour = 12
        return calendar.date(from: components)
    }
}

private struct SearchResponse: Decodable {
    let results: [TVResult]
}

private struct FindResponse: Decodable {
    let tvResults: [TVResult]
    let episodeResults: [EpisodeResult]

    enum CodingKeys: String, CodingKey {
        case tvResults = "tv_results"
        case episodeResults = "tv_episode_results"
    }
}

private struct TVResult: Decodable {
    let id: Int
    let name: String
    let overview: String
    let firstAirDate: String?
    let posterPath: String?

    enum CodingKeys: String, CodingKey {
        case id, name, overview
        case firstAirDate = "first_air_date"
        case posterPath = "poster_path"
    }
}

private struct ShowResponse: Decodable {
    let id: Int
    let name: String
    let overview: String
    let status: String
    let genres: [Genre]
    let posterPath: String?
    let backdropPath: String?
    let episodeRunTime: [Int]
    let seasons: [SeasonSummary]
    let externalIDs: ExternalIDs?

    struct Genre: Decodable { let name: String }
    struct SeasonSummary: Decodable {
        let seasonNumber: Int
        enum CodingKeys: String, CodingKey { case seasonNumber = "season_number" }
    }
    struct ExternalIDs: Decodable {
        let tvdbID: Int?
        enum CodingKeys: String, CodingKey { case tvdbID = "tvdb_id" }
    }
    enum CodingKeys: String, CodingKey {
        case id, name, overview, status, genres, seasons
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case episodeRunTime = "episode_run_time"
        case externalIDs = "external_ids"
    }
}

private struct SeasonResponse: Decodable {
    let episodes: [EpisodeResult]
}

private struct EpisodeResult: Decodable {
    let id: Int
    let name: String
    let overview: String
    let airDate: String?
    let episodeNumber: Int
    let seasonNumber: Int
    let stillPath: String?
    let runtime: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, overview, runtime
        case airDate = "air_date"
        case episodeNumber = "episode_number"
        case seasonNumber = "season_number"
        case stillPath = "still_path"
    }
}

private struct ErrorResponse: Decodable {
    let statusMessage: String
    enum CodingKeys: String, CodingKey { case statusMessage = "status_message" }
}
