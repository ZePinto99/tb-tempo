import SwiftData
import SwiftUI

enum ShowSort: String, CaseIterable, Identifiable {
    case title
    case progress
    case activity
    case nextRelease
    var id: String { rawValue }
    var title: String {
        switch self {
        case .title: String(localized: "Title")
        case .progress: String(localized: "Progress")
        case .activity: String(localized: "Recent activity")
        case .nextRelease: String(localized: "Next release")
        }
    }
}

struct ShowsView: View {
    @Query private var shows: [Show]
    @State private var search = ""
    @State private var state: LibraryState?
    @State private var sort: ShowSort = .title
    @State private var showingSearch = false

    private var filtered: [Show] {
        let selected = shows.filter {
            (state == nil || $0.libraryState == state) && (search.isEmpty || $0.title.localizedStandardContains(search))
        }
        switch sort {
        case .title: return selected.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .progress: return selected.sorted { $0.progress > $1.progress }
        case .activity: return selected.sorted { ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast) }
        case .nextRelease: return selected.sorted { ($0.nextRelease ?? .distantFuture) < ($1.nextRelease ?? .distantFuture) }
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 142), spacing: 16)]

    var body: some View {
        ScrollView {
            if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
                    .padding(.top, 70)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                    ForEach(filtered) { show in
                        NavigationLink(value: show) {
                            VStack(alignment: .leading, spacing: 8) {
                                PosterView(show: show, width: 142)
                                Text(show.title).font(.headline).lineLimit(2)
                                ProgressView(value: show.progress).tint(Brand.coral)
                                Text("\(show.watchedRegularEpisodes.count)/\(show.regularEpisodes.count) · \(show.libraryState.title)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "Shows"))
        .searchable(text: $search, prompt: String(localized: "Search your shows"))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button(String(localized: "All")) { state = nil }
                    ForEach(LibraryState.allCases) { value in Button(value.title) { state = value } }
                    Divider()
                    Picker(String(localized: "Sort"), selection: $sort) {
                        ForEach(ShowSort.allCases) { Text($0.title).tag($0) }
                    }
                } label: { Label(String(localized: "Filter and sort"), systemImage: "line.3.horizontal.decrease.circle") }
                Button { showingSearch = true } label: { Label(String(localized: "Find a series"), systemImage: "plus") }
            }
        }
        .navigationDestination(for: Show.self) { SeriesDetailView(show: $0) }
        .sheet(isPresented: $showingSearch) { NavigationStack { SearchCatalogView() } }
    }
}
