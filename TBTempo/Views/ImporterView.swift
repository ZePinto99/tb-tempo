import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ImporterView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showingPicker = false
    @State private var isReading = false
    @State private var preview: TVTimeImportPreview?
    @State private var result: TVTimeImportResult?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Text(String(localized: "Select the original GDPR ZIP. TB Tempo reads only an explicit allowlist of tracking and statistics CSV files. The archive is never copied into the app library."))
                    .foregroundStyle(.secondary)
                Button {
                    showingPicker = true
                } label: {
                    Label(String(localized: "Choose TV Time ZIP"), systemImage: "doc.badge.plus")
                }
                .disabled(isReading)
                if isReading { HStack { ProgressView(); Text(String(localized: "Inspecting archive…")) } }
            } header: { Text(String(localized: "Optional Migration")) }

            if let preview {
                Section(String(localized: "Preview")) {
                    countRow(String(localized: "Detected series"), preview.series.count)
                    countRow(String(localized: "Watched episodes ready"), preview.watches.count)
                    countRow(String(localized: "Stopped series"), preview.stoppedCount)
                    countRow(String(localized: "Duplicates skipped"), preview.duplicateCount)
                    countRow(String(localized: "Unresolved records"), preview.unresolved.count)
                    countRow(String(localized: "Unknown runtimes"), preview.unknownRuntimeCount)
                }
                Section(String(localized: "Reconciliation")) {
                    if let exported = preview.exportedEpisodeCount {
                        LabeledContent(String(localized: "Exported aggregate episodes"), value: exported.formatted())
                        LabeledContent(String(localized: "Individual records accepted"), value: preview.watches.count.formatted())
                    }
                    if let exported = preview.exportedViewingMinutes {
                        LabeledContent(String(localized: "Exported aggregate time"), value: StatisticsEngine.duration(exported))
                    }
                    LabeledContent(String(localized: "Calculated from records"), value: StatisticsEngine.duration(preview.calculatedViewingMinutes))
                    Text(String(localized: "Individual watch records take precedence. Aggregate differences are retained in the import report; missing runtimes and unresolved coordinate collisions are never guessed."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if !preview.unresolved.isEmpty {
                    Section(String(localized: "Unresolved sample")) {
                        ForEach(preview.unresolved.prefix(8)) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(record.seriesTitle) · S\(record.seasonNumber ?? 0)E\(record.episodeNumber ?? 0)")
                                Text(record.reason).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if preview.unresolved.count > 8 { Text(String(localized: "And \(preview.unresolved.count - 8) more…")).foregroundStyle(.secondary) }
                    }
                }
                Section {
                    Button(String(localized: "Confirm Atomic Import")) { commit(preview) }
                        .buttonStyle(.borderedProminent)
                } footer: {
                    Text(String(localized: "The archive fingerprint and stable event keys make the import idempotent. Nothing is written until you confirm."))
                }
            }

            if let result {
                Section(String(localized: "Import Complete")) {
                    Label(String(localized: "Imported \(result.insertedSeries) series and \(result.insertedWatches) watch records."), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if result.unresolved > 0 { Text(String(localized: "\(result.unresolved) records are available under Unresolved Matches in Settings.")) }
                    if let exported = result.exportedViewingMinutes {
                        let difference = result.calculatedViewingMinutes - exported
                        Text(String(localized: "Calculated viewing time differs from the export aggregate by \(StatisticsEngine.duration(abs(difference))). This usually reflects missing per-episode runtimes or legacy counters."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            }
        }
        .navigationTitle(String(localized: "Import TV Time"))
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.zip], allowsMultipleSelection: false) { response in
            guard case .success(let urls) = response, let url = urls.first else {
                if case .failure(let error) = response { errorMessage = error.localizedDescription }
                return
            }
            load(url)
        }
    }

    private func countRow(_ title: String, _ count: Int) -> some View {
        LabeledContent(title, value: count.formatted())
    }

    private func load(_ url: URL) {
        isReading = true
        preview = nil
        result = nil
        errorMessage = nil
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                preview = try await Task.detached(priority: .userInitiated) { try TVTimeImporter.preview(url: url) }.value
            } catch {
                errorMessage = error.localizedDescription
            }
            isReading = false
        }
    }

    private func commit(_ preview: TVTimeImportPreview) {
        do {
            result = try TVTimeImporter.commit(preview, to: modelContext)
            self.preview = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct UnresolvedMatchesView: View {
    @Query(sort: \UnresolvedImportRecord.createdAt, order: .reverse) private var records: [UnresolvedImportRecord]

    var body: some View {
        List(records) { record in
            NavigationLink {
                UnresolvedResolutionView(record: record)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.seriesTitle).font(.headline)
                    Text("S\(record.seasonNumber ?? 0)E\(record.episodeNumber ?? 0)")
                    Text(record.reason).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .overlay {
            if records.isEmpty { ContentUnavailableView(String(localized: "No unresolved matches"), systemImage: "checkmark.seal") }
        }
        .navigationTitle(String(localized: "Unresolved Matches"))
    }
}

private struct UnresolvedResolutionView: View {
    let record: UnresolvedImportRecord
    @Query private var shows: [Show]
    @Query private var events: [WatchEvent]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var episodes: [Episode] {
        shows.filter { show in
            if let tvdbID = record.tvdbSeriesID { return show.tvdbID == tvdbID }
            return show.normalizedTitle == TextNormalizer.title(record.seriesTitle)
        }
        .flatMap(\.episodes)
        .filter {
            search.isEmpty || $0.title.localizedStandardContains(search) || $0.coordinate.localizedStandardContains(search)
        }
        .sorted(by: Episode.canonicalOrder)
    }

    var body: some View {
        List {
            Section {
                Text(String(localized: "Choose the exact episode. TB Tempo will attach the preserved watch date only after you confirm this manual match."))
                    .foregroundStyle(.secondary)
            }
            Section(String(localized: "Candidate Episodes")) {
                ForEach(episodes) { episode in
                    Button {
                        resolve(to: episode)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(episode.coordinate) · \(episode.title)").foregroundStyle(.primary)
                            if let date = episode.airDate { Text(date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
        .overlay {
            if episodes.isEmpty {
                ContentUnavailableView(String(localized: "No episode candidates"), systemImage: "arrow.clockwise", description: Text(String(localized: "Refresh this series’ metadata, then return to resolve the record.")))
            }
        }
        .searchable(text: $search, prompt: String(localized: "Episode title or number"))
        .navigationTitle(String(localized: "Resolve Match"))
    }

    private func resolve(to episode: Episode) {
        if !events.contains(where: { $0.stableKey == record.stableKey }) {
            let event = WatchEvent(stableKey: record.stableKey, watchedAt: record.watchedAt ?? Date(), source: .tvTimeV2, isEstimatedDate: record.watchedAt == nil, episode: episode)
            modelContext.insert(event)
            episode.watchEvents.append(event)
        }
        modelContext.delete(record)
        try? modelContext.save()
        dismiss()
    }
}
