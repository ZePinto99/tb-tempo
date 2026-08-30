import Foundation

protocol CatalogProviding: Sendable {
    func search(query: String) async throws -> [CatalogSearchResult]
    func show(tmdbID: Int) async throws -> CatalogShow
    func lookupTVDBSeries(id: Int) async throws -> CatalogSearchResult?
    func lookupTVDBEpisode(id: Int) async throws -> CatalogEpisode?
    func imageData(path: String, width: Int) async throws -> Data
}

enum CatalogError: LocalizedError {
    case missingToken
    case invalidResponse
    case providerMessage(String)
    case noMatch

    var errorDescription: String? {
        switch self {
        case .missingToken:
            String(localized: "TMDB is not configured. Add your read token to Config/TMDBConfig.xcconfig.")
        case .invalidResponse:
            String(localized: "The catalog returned an unexpected response.")
        case .providerMessage(let message): message
        case .noMatch: String(localized: "No unambiguous catalog match was found.")
        }
    }
}

struct CatalogConfiguration: Sendable {
    let token: String

    static func bundled() -> CatalogConfiguration {
        let token = Bundle.main.object(forInfoDictionaryKey: "TMDBReadAccessToken") as? String ?? ""
        return CatalogConfiguration(token: token.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var isConfigured: Bool {
        !token.isEmpty && token != "paste_your_personal_read_access_token_here"
    }
}
