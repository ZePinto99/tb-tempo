import Observation
import SwiftData
import SwiftUI
import UIKit

@MainActor
@Observable
final class ProgressController {
    private struct EpisodeState {
        let episode: Episode
        let events: [WatchEventSnapshot]
    }

    private struct UndoAction {
        let states: [EpisodeState]
        let message: String
    }

    private(set) var undoMessage: String?
    private var undoAction: UndoAction?
    private var dismissalTask: Task<Void, Never>?

    func toggle(_ episode: Episode, in context: ModelContext) {
        setWatched([episode], watched: !episode.isWatched, message: episode.isWatched ? String(localized: "Marked unwatched") : String(localized: "Marked watched"), in: context)
    }

    func setSeason(_ seasonNumber: Int, in show: Show, watched: Bool, context: ModelContext) {
        let episodes = show.episodes.filter { $0.seasonNumber == seasonNumber }
        setWatched(episodes, watched: watched, message: watched ? String(localized: "Season marked watched") : String(localized: "Season marked unwatched"), in: context)
    }

    func setThrough(_ episode: Episode, in show: Show, context: ModelContext) {
        let affected = show.episodes.filter {
            guard $0.isSpecial == episode.isSpecial else { return false }
            return $0.seasonNumber < episode.seasonNumber || ($0.seasonNumber == episode.seasonNumber && $0.episodeNumber <= episode.episodeNumber)
        }
        setWatched(affected, watched: true, message: String(localized: "Progress updated"), in: context)
    }

    func undo(in context: ModelContext) {
        guard let undoAction else { return }
        dismissalTask?.cancel()
        for state in undoAction.states {
            state.episode.watchEvents.forEach(context.delete)
            state.episode.watchEvents.removeAll()
            for snapshot in state.events {
                let event = WatchEvent(
                    stableKey: snapshot.stableKey,
                    watchedAt: snapshot.watchedAt,
                    source: snapshot.source,
                    isEstimatedDate: snapshot.isEstimatedDate,
                    episode: state.episode
                )
                context.insert(event)
                state.episode.watchEvents.append(event)
            }
        }
        try? context.save()
        self.undoAction = nil
        undoMessage = nil
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func setWatched(_ episodes: [Episode], watched: Bool, message: String, in context: ModelContext) {
        guard !episodes.isEmpty else { return }
        let states = episodes.map { episode in
            EpisodeState(
                episode: episode,
                events: episode.watchEvents.map {
                    WatchEventSnapshot(stableKey: $0.stableKey, watchedAt: $0.watchedAt, source: $0.source, isEstimatedDate: $0.isEstimatedDate)
                }
            )
        }
        for episode in episodes {
            if watched {
                if !episode.isWatched {
                    let event = WatchEvent(stableKey: "manual:\(UUID().uuidString)", watchedAt: Date(), source: .manual, episode: episode)
                    context.insert(event)
                    episode.watchEvents.append(event)
                }
            } else {
                episode.watchEvents.forEach(context.delete)
                episode.watchEvents.removeAll()
            }
            episode.show?.lastActivityAt = Date()
        }
        do {
            try context.save()
            undoAction = UndoAction(states: states, message: message)
            undoMessage = message
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            scheduleDismissal()
        } catch {
            context.rollback()
        }
    }

    private func scheduleDismissal() {
        dismissalTask?.cancel()
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            self?.undoAction = nil
            self?.undoMessage = nil
        }
    }
}
