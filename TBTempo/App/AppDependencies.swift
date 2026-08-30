import Observation
import SwiftData

@MainActor
@Observable
final class AppDependencies {
    let container: ModelContainer
    let catalog: any CatalogProviding
    let progress: ProgressController
    let notificationScheduler: NotificationScheduling
    let refresh: MetadataRefreshCoordinator

    init(container: ModelContainer) {
        self.container = container
        let catalog = TMDBCatalogProvider()
        let scheduler = LocalNotificationScheduler()
        self.catalog = catalog
        notificationScheduler = scheduler
        progress = ProgressController()
        refresh = MetadataRefreshCoordinator(catalog: catalog, container: container, notificationScheduler: scheduler)
    }
}
