import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Query private var shows: [Show]
    @Query(sort: \ImportReceipt.importedAt, order: .reverse) private var receipts: [ImportReceipt]
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var modelContext
    @AppStorage("notificationsEnabled") private var notificationsEnabled = false
    @AppStorage("notificationHour") private var notificationHour = 9
    @AppStorage("appAppearance") private var appAppearance = AppAppearance.system.rawValue
    @State private var explainingNotifications = false
    @State private var backupWarning = false
    @State private var shareURL: URL?
    @State private var csvURL: URL?
    @State private var showingBackupPicker = false
    @State private var backupPreview: BackupPreview?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section(String(localized: "Appearance")) {
                Picker(String(localized: "Color scheme"), selection: $appAppearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(String(localized: "Migration")) {
                NavigationLink { ImporterView() } label: { Label(String(localized: "Import TV Time History"), systemImage: "arrow.down.doc") }
                NavigationLink { UnresolvedMatchesView() } label: { Label(String(localized: "Unresolved Matches"), systemImage: "questionmark.diamond") }
                if let receipt = receipts.first {
                    LabeledContent(String(localized: "Last import"), value: receipt.importedAt.formatted(date: .abbreviated, time: .shortened))
                }
            }

            Section {
                Button { backupWarning = true } label: { Label(String(localized: "Export TB Tempo Backup"), systemImage: "square.and.arrow.up") }
                Button { showingBackupPicker = true } label: { Label(String(localized: "Import TB Tempo Backup"), systemImage: "square.and.arrow.down") }
                Button { exportCSV() } label: { Label(String(localized: "Export Viewing History CSV"), systemImage: "tablecells") }
                if let shareURL { ShareLink(item: shareURL) { Label(String(localized: "Share Latest Backup"), systemImage: "paperplane") } }
                if let csvURL { ShareLink(item: csvURL) { Label(String(localized: "Share Latest CSV"), systemImage: "paperplane") } }
            } header: { Text(String(localized: "Portable Backups")) } footer: {
                Text(String(localized: "Backups are versioned .tbtempo ZIP packages containing JSON. Artwork is not included because it can be refreshed."))
            }

            Section {
                Toggle(String(localized: "Upcoming episode notifications"), isOn: Binding(
                    get: { notificationsEnabled },
                    set: { enabled in
                        if enabled { explainingNotifications = true } else { notificationsEnabled = false; Task { await dependencies.refresh.rescheduleNotificationsFromLibrary() } }
                    }
                ))
                Picker(String(localized: "Morning time"), selection: $notificationHour) {
                    ForEach(5..<13, id: \.self) { hour in Text(DateComponents(calendar: .current, hour: hour).date?.formatted(date: .omitted, time: .shortened) ?? "\(hour):00").tag(hour) }
                }
                .disabled(!notificationsEnabled)
            } header: { Text(String(localized: "Notifications")) } footer: {
                Text(String(localized: "TB Tempo schedules a rolling window within the 90-day Upcoming horizon. Background refresh is best-effort; open the app periodically to refresh delayed releases."))
            }

            Section(String(localized: "Catalog")) {
                Button {
                    Task { await dependencies.refresh.refreshAll() }
                } label: {
                    if dependencies.refresh.isRefreshing { Label(String(localized: "Refreshing Metadata…"), systemImage: "arrow.clockwise") }
                    else { Label(String(localized: "Refresh All Metadata"), systemImage: "arrow.clockwise") }
                }
                .disabled(dependencies.refresh.isRefreshing)
                if let error = dependencies.refresh.lastError { Text(error).font(.footnote).foregroundStyle(.orange) }
                LabeledContent(String(localized: "TMDB token"), value: CatalogConfiguration.bundled().isConfigured ? String(localized: "Configured") : String(localized: "Not configured"))
            }

            Section(String(localized: "Information")) {
                NavigationLink { AboutView() } label: { Label(String(localized: "About & Attribution"), systemImage: "info.circle") }
                NavigationLink { PrivacyView() } label: { Label(String(localized: "Privacy"), systemImage: "hand.raised") }
            }

            if let errorMessage { Section { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) } }
        }
        .navigationTitle(String(localized: "Settings"))
        .alert(String(localized: "Get release reminders?"), isPresented: $explainingNotifications) {
            Button(String(localized: "Not Now"), role: .cancel) { notificationsEnabled = false }
            Button(String(localized: "Allow Notifications")) { requestNotifications() }
        } message: {
            Text(String(localized: "TB Tempo can remind you on the morning a followed episode is released. Permission is requested only if you continue."))
        }
        .alert(String(localized: "Private, unencrypted backup"), isPresented: $backupWarning) {
            Button(String(localized: "Cancel"), role: .cancel) {}
            Button(String(localized: "Create Backup")) { exportBackup() }
        } message: {
            Text(String(localized: "The backup contains your viewing history in readable JSON. Store and share it carefully."))
        }
        .fileImporter(isPresented: $showingBackupPicker, allowedContentTypes: [.zip, UTType(filenameExtension: "tbtempo")!], allowsMultipleSelection: false) { response in
            guard case .success(let urls) = response, let url = urls.first else {
                if case .failure(let error) = response { errorMessage = error.localizedDescription }
                return
            }
            loadBackup(url)
        }
        .sheet(item: $backupPreview) { preview in BackupRestoreView(preview: preview) }
        .onChange(of: notificationHour) { _, _ in Task { await dependencies.refresh.rescheduleNotificationsFromLibrary() } }
    }

    private func requestNotifications() {
        Task {
            do {
                notificationsEnabled = try await dependencies.notificationScheduler.requestAuthorization()
                await dependencies.refresh.rescheduleNotificationsFromLibrary()
            } catch { errorMessage = error.localizedDescription; notificationsEnabled = false }
        }
    }

    private func exportBackup() {
        do { shareURL = try BackupService.export(shows: shows); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    private func exportCSV() {
        do { csvURL = try BackupService.exportViewingHistoryCSV(shows: shows); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    private func loadBackup(_ url: URL) {
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do { backupPreview = try BackupService.preview(url: url); errorMessage = nil }
            catch { errorMessage = error.localizedDescription }
        }
    }
}

extension BackupPreview: Identifiable {
    var id: Date { manifest.createdAt }
}

private struct BackupRestoreView: View {
    let preview: BackupPreview
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var mode: BackupImportMode = .merge
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Backup Preview")) {
                    LabeledContent(String(localized: "Created"), value: preview.manifest.createdAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent(String(localized: "Series"), value: preview.showCount.formatted())
                    LabeledContent(String(localized: "Episodes"), value: preview.episodeCount.formatted())
                    LabeledContent(String(localized: "Watch events"), value: preview.watchCount.formatted())
                }
                Section {
                    Picker(String(localized: "Restore mode"), selection: $mode) {
                        ForEach(BackupImportMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(mode == .merge ? String(localized: "Merge keeps local data and adds stable records that are missing.") : String(localized: "Replace atomically removes the local library and restores this backup."))
                        .font(.footnote).foregroundStyle(mode == .replace ? .red : .secondary)
                    Button(String(localized: "Restore Backup")) { restore() }.buttonStyle(.borderedProminent)
                }
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(.orange) } }
            }
            .navigationTitle(String(localized: "Restore Backup"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(String(localized: "Cancel")) { dismiss() } } }
        }
    }

    private func restore() {
        do { try BackupService.restore(preview, mode: mode, context: modelContext); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Brand.gradient)
                        Image(systemName: "play.rectangle.on.rectangle").font(.system(size: 38, weight: .semibold)).foregroundStyle(.white)
                    }
                    .frame(width: 84, height: 84)
                    Text(String(localized: "TB Tempo")).font(.title.bold())
                    Text(String(localized: "A private, local-first rhythm for your series."))
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding()
            }
            Section(String(localized: "TMDB Attribution")) {
                Text(String(localized: "This product uses the TMDB API but is not endorsed or certified by TMDB."))
                Link(String(localized: "Visit The Movie Database"), destination: URL(string: "https://www.themoviedb.org")!)
            }
            Section(String(localized: "Identity")) {
                Text(String(localized: "TB Tempo’s name, app icon, color system, and interface are original. Catalog artwork belongs to its respective rights holders."))
            }
        }
        .navigationTitle(String(localized: "About"))
    }
}

private struct PrivacyView: View {
    var body: some View {
        List {
            Label(String(localized: "Your library and viewing history stay on this device."), systemImage: "iphone")
            Label(String(localized: "No account, CloudKit, analytics, ads, or custom backend."), systemImage: "person.crop.circle.badge.xmark")
            Label(String(localized: "Internet access is used only for TMDB metadata and artwork."), systemImage: "network")
            Label(String(localized: "Exported backups are unencrypted and contain private history."), systemImage: "lock.open")
        }
        .navigationTitle(String(localized: "Privacy"))
    }
}
