import SwiftData
import SwiftUI

@main
struct TBTempoApp: App {
    private let container: ModelContainer
    @State private var dependencies: AppDependencies

    init() {
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        }
        let schema = Schema([
            Show.self,
            Episode.self,
            WatchEvent.self,
            ImportReceipt.self,
            UnresolvedImportRecord.self
        ])
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-UITesting")
        let configuration = ModelConfiguration("TBTempo", schema: schema, isStoredInMemoryOnly: isUITesting)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            self.container = container
            _dependencies = State(initialValue: AppDependencies(container: container))
        } catch {
            fatalError("Unable to open the local TB Tempo library: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(dependencies)
        }
        .modelContainer(container)
    }
}
