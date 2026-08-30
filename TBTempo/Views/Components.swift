import SwiftUI

enum Brand {
    static let indigo = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.16, green: 0.12, blue: 0.46, alpha: 1)
            : UIColor(red: 0.10, green: 0.06, blue: 0.38, alpha: 1)
    })
    static let violet = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.56, green: 0.39, blue: 0.98, alpha: 1)
            : UIColor(red: 0.42, green: 0.20, blue: 0.92, alpha: 1)
    })
    static let coral = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.45, blue: 0.38, alpha: 1)
            : UIColor(red: 1.00, green: 0.33, blue: 0.25, alpha: 1)
    })
    static let gradient = LinearGradient(colors: [violet, coral], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct ArtworkView: View {
    let data: Data?
    let systemName: String

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(colors: [Brand.indigo, Brand.violet.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: systemName)
                        .font(.largeTitle)
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

struct PosterView: View {
    let show: Show
    var width: CGFloat = 112

    var body: some View {
        ArtworkView(data: show.posterData, systemName: "tv")
            .frame(width: width, height: width * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.12))
            }
            .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
            .accessibilityLabel(show.title)
    }
}

struct ProgressPill: View {
    let watched: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ProgressView(value: total == 0 ? 0 : Double(watched) / Double(total))
                .tint(Brand.coral)
                .frame(width: 58)
            Text("\(watched)/\(total)")
                .font(.caption.monospacedDigit())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "\(watched) of \(total) episodes watched"))
    }
}

struct EpisodeCard: View {
    let episode: Episode
    let showTitle: String
    var prominent = false
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: 14) {
            ArtworkView(data: episode.stillData ?? episode.show?.backdropData, systemName: "play.rectangle")
                .frame(width: prominent ? 132 : 102, height: prominent ? 82 : 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(showTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(episode.title.isEmpty ? String(localized: "Episode \(episode.episodeNumber)") : episode.title)
                    .font(prominent ? .headline : .subheadline.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(episode.coordinate)
                    if let runtime = episode.effectiveRuntime { Text("\(runtime) min") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button {
                withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .snappy) {
                    dependencies.progress.toggle(episode, in: modelContext)
                }
                Task { await dependencies.refresh.rescheduleNotificationsFromLibrary() }
            } label: {
                Image(systemName: episode.isWatched ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(episode.isWatched ? Brand.coral : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(episode.isWatched ? String(localized: "Mark unwatched") : String(localized: "Mark watched"))
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

struct UndoBar: View {
    @Environment(AppDependencies.self) private var dependencies
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if let message = dependencies.progress.undoMessage {
            HStack {
                Text(message)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button(String(localized: "Undo")) {
                    withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : .snappy) {
                        dependencies.progress.undo(in: modelContext)
                    }
                    Task { await dependencies.refresh.rescheduleNotificationsFromLibrary() }
                }
                .fontWeight(.bold)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
            .padding(.horizontal)
            .padding(.bottom, 2)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain)
        }
    }
}

struct MetricCard: View {
    let value: String
    let label: String
    let systemName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemName)
                .foregroundStyle(Brand.gradient)
                .font(.title2)
            Text(value)
                .font(.title2.bold())
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
