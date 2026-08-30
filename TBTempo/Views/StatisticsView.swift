import SwiftData
import SwiftUI

enum StatisticsBreakdown: String, CaseIterable, Identifiable {
    case series
    case season
    case month
    case year
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct StatisticsView: View {
    @Query private var shows: [Show]
    @State private var breakdown = StatisticsBreakdown.series

    private var report: StatisticsReport { StatisticsEngine.report(shows: shows) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    MetricCard(value: report.watchedEpisodeCount.formatted(), label: String(localized: "episodes watched"), systemName: "checkmark.circle")
                    MetricCard(value: StatisticsEngine.duration(report.totalMinutes), label: String(localized: "viewing time"), systemName: "hourglass")
                }
                if report.watchEventCount > report.watchedEpisodeCount {
                    Label(String(localized: "\(report.watchEventCount - report.watchedEpisodeCount) rewatches are included in viewing time."), systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if report.unknownRuntimeEventCount > 0 {
                    Label(String(localized: "\(report.unknownRuntimeEventCount) watch events have unknown runtime and add zero minutes."), systemImage: "questionmark.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Picker(String(localized: "Breakdown"), selection: $breakdown) {
                    ForEach(StatisticsBreakdown.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                breakdownList
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "Statistics"))
    }

    @ViewBuilder private var breakdownList: some View {
        let rows: [(String, Int, Int)] = switch breakdown {
        case .series: report.bySeries.map { ($0.title, $0.eventCount, $0.minutes) }
        case .season: report.bySeason.map { ($0.label, $0.eventCount, $0.minutes) }
        case .month: report.byMonth.map { ($0.label, $0.eventCount, $0.minutes) }
        case .year: report.byYear.map { ($0.label, $0.eventCount, $0.minutes) }
        }
        if rows.isEmpty {
            ContentUnavailableView(String(localized: "No viewing history yet"), systemImage: "chart.bar")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(row.0).font(.subheadline.weight(.semibold))
                            Text(String(localized: "\(row.1) watch events")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(StatisticsEngine.duration(row.2)).font(.caption.weight(.medium)).multilineTextAlignment(.trailing)
                    }
                    .padding()
                    if row.0 != rows.last?.0 { Divider().padding(.leading) }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}
