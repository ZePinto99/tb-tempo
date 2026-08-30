import SwiftData
import SwiftUI

struct SearchCatalogView: View {
    var matchingShow: Show?
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var existingShows: [Show]
    @State private var query = ""
    @State private var results: [CatalogSearchResult] = []
    @State private var isSearching = false
    @State private var addingID: Int?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
            ForEach(results) { result in
                HStack(spacing: 12) {
                    AsyncImage(url: result.posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w300\($0)") }) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(Brand.indigo.gradient).overlay { Image(systemName: "tv").foregroundStyle(.white) }
                    }
                    .frame(width: 58, height: 86).clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(result.title).font(.headline)
                        if let date = result.firstAirDate { Text(date.formatted(.dateTime.year())).font(.caption).foregroundStyle(.secondary) }
                        Text(result.overview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    if matchingShow == nil, existingShows.contains(where: { $0.tmdbID == result.id }) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.coral).accessibilityLabel(String(localized: "Already followed"))
                    } else if addingID == result.id {
                        ProgressView()
                    } else {
                        Button {
                            add(result)
                        } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Follow \(result.title)"))
                    }
                }
            }
        }
        .overlay {
            if query.isEmpty {
                ContentUnavailableView(String(localized: "Find your next series"), systemImage: "magnifyingglass", description: Text(String(localized: "Search the TMDB catalog by title.")))
            } else if isSearching && results.isEmpty { ProgressView() }
        }
        .navigationTitle(matchingShow == nil ? String(localized: "Find Series") : String(localized: "Match Series"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: String(localized: "Series title"))
        .task(id: query) {
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { results = []; return }
            do {
                try await Task.sleep(for: .milliseconds(350))
                isSearching = true
                defer { isSearching = false }
                results = try await dependencies.catalog.search(query: query)
                errorMessage = nil
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Done")) { dismiss() } } }
    }

    private func add(_ result: CatalogSearchResult) {
        addingID = result.id
        Task {
            do {
                if let matchingShow {
                    guard !existingShows.contains(where: { $0 !== matchingShow && $0.tmdbID == result.id }) else {
                        throw CatalogError.providerMessage(String(localized: "That TMDB series is already in your library."))
                    }
                    matchingShow.tmdbID = result.id
                    try modelContext.save()
                    await dependencies.refresh.refresh([matchingShow])
                    if let refreshError = dependencies.refresh.lastError {
                        errorMessage = refreshError
                    } else {
                        errorMessage = nil
                        dismiss()
                    }
                } else {
                    _ = try await dependencies.refresh.add(searchResult: result)
                    errorMessage = nil
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            addingID = nil
        }
    }
}
