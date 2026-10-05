import SwiftUI

// MARK: - Statistics tab (mirrors the web StatisticsTab exactly:
// Average Blood Pressure vs Previous Period, Detailed Statistics with
// vs Prev. change indicators, Reference Ranges)

struct StatisticsView: View {
    @ObservedObject var store = BPStore.shared
    @EnvironmentObject var filters: FilterState

    // Normal thresholds from the HTN Canada 2025 guideline (web normalThresholds)
    private let sysConfig = ChangeConfig.lowerIsBetter(optimalMax: 130)
    private let diaConfig = ChangeConfig.lowerIsBetter(optimalMax: 80)
    private let pulseConfig = ChangeConfig.midpoint(mid: 80, bufferMin: 70, bufferMax: 90)
    private let ppConfig = ChangeConfig.midpoint(mid: 45, bufferMin: 40, bufferMax: 50)
    private let mapConfig = ChangeConfig.midpoint(mid: 85, bufferMin: 80, bufferMax: 90)

    private var filtered: [BPSession] {
        filterSessions(
            store.sessions,
            dateRange: filters.dateRange,
            timeOfDay: filters.timeOfDay,
            customStartDate: filters.customStartDate,
            customEndDate: filters.customEndDate
        )
    }

    private var previousSessions: [BPSession] {
        guard let period = filters.dateRange.previousPeriod() else { return [] }
        return store.sessions.filter { s in
            guard let d = parseDateOnly(s.date) else { return false }
            let inPeriod = d >= period.start && d < period.end
            let todOK = filters.timeOfDay == nil || s.timeOfDay == filters.timeOfDay
            return inPeriod && todOK
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BPFilterBar(filters: filters)
                    .padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                    if let stats = calculateFullStats(sessions: filtered) {
                        // Average BP header
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Average Blood Pressure")
                                    .font(SomaFont.regular(13))
                                    .foregroundColor(SomaTheme.muted)
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text("\(rounded(stats.systolic.avg))/\(rounded(stats.diastolic.avg))")
                                        .font(SomaFont.bold(32))
                                        .foregroundColor(SomaTheme.text)
                                    Text("mmHg")
                                        .font(SomaFont.regular(16))
                                        .foregroundColor(SomaTheme.muted)
                                }
                            }
                            Spacer()
                            if let prevStats = calculateFullStats(sessions: previousSessions) {
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Previous Period")
                                        .font(SomaFont.regular(13))
                                        .foregroundColor(SomaTheme.muted)
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        Text("\(rounded(prevStats.systolic.avg))/\(rounded(prevStats.diastolic.avg))")
                                            .font(SomaFont.bold(20))
                                            .foregroundColor(SomaTheme.muted)
                                        Text("mmHg")
                                            .font(SomaFont.regular(13))
                                            .foregroundColor(SomaTheme.muted)
                                    }
                                }
                            } else if filters.dateRange != .all {
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Previous Period")
                                        .font(SomaFont.regular(13))
                                        .foregroundColor(SomaTheme.muted)
                                    Text("No data")
                                        .font(SomaFont.regular(13))
                                        .italic()
                                        .foregroundColor(SomaTheme.muted)
                                }
                            }
                        }

                        Text("\(stats.count) reading\(stats.count == 1 ? "" : "s") (\(formatDateRangeLabel(sessions: filtered)))")
                            .font(SomaFont.regular(11))
                            .foregroundColor(SomaTheme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        Divider().background(SomaTheme.border)

                        // Detailed Statistics
                        Text("Detailed Statistics")
                            .font(SomaFont.bold(16))
                            .foregroundColor(SomaTheme.text)
                            .padding(.top, 16)
                            .padding(.bottom, 4)

                        let prevStats = calculateFullStats(sessions: previousSessions)
                        StatsTable(
                            current: stats, previous: prevStats,
                            configs: [
                                ("Systolic", \.systolic, sysConfig),
                                ("Diastolic", \.diastolic, diaConfig),
                                ("Pulse", \.pulse, pulseConfig),
                                ("PP", \.pp, ppConfig),
                                ("MAP", \.map, mapConfig),
                            ]
                        )

                        if prevStats == nil, filters.dateRange != .all {
                            Text("No previous period data available for comparison")
                                .font(SomaFont.regular(11))
                                .foregroundColor(SomaTheme.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 10)
                        }
                        if filters.dateRange == .all {
                            Text("Select a date range to see comparison with previous period")
                                .font(SomaFont.regular(11))
                                .foregroundColor(SomaTheme.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 10)
                        }

                        Divider().background(SomaTheme.border).padding(.top, 14)

                        // Reference Ranges (matches web exactly)
                        Text("Reference Ranges")
                            .font(SomaFont.bold(16))
                            .foregroundColor(SomaTheme.text)
                            .padding(.top, 16)
                            .padding(.bottom, 4)
                        VStack(spacing: 0) {
                            ReferenceRow(label: "Pulse (resting)", value: "60–100 bpm", sub: "(40–100 for athletes)")
                            ReferenceRow(label: "Pulse Pressure", value: "30–60 mmHg", sub: nil)
                            ReferenceRow(label: "Mean Arterial Pressure", value: "70–100 mmHg", sub: nil, last: true)
                        }
                    } else {
                        Text("No readings yet")
                            .foregroundColor(SomaTheme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    }
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 18)
                }
            }
            .background(SomaTheme.background)
            .navigationTitle("Statistics")
        }
        .tint(SomaTheme.rose)
    }

    private func rounded(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(v.rounded()))"
    }
}

// MARK: - Detailed statistics table

struct StatsTable: View {
    let current: FullStats
    let previous: FullStats?
    /// (label, key path into FullStats, change config)
    let configs: [(String, KeyPath<FullStats, StatValues>, ChangeConfig)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Metric")
                    .frame(width: 72, alignment: .leading)
                Spacer()
                Text("Min").frame(width: 48)
                Text("Max").frame(width: 48)
                Text("Avg").frame(width: 48)
                Text("vs Prev.").frame(minWidth: 64)
            }
            .font(SomaFont.regular(12))
            .foregroundColor(SomaTheme.muted)
            .padding(.vertical, 8)
            Divider().background(SomaTheme.border)

            ForEach(configs, id: \.0) { label, keyPath, config in
                let cur = current[keyPath: keyPath]
                // Skip the pulse row when there is no pulse data (matches web)
                if label != "Pulse" || cur.avg != nil {
                    HStack {
                        Text(label)
                            .font(SomaFont.bold(13))
                            .foregroundColor(SomaTheme.text)
                            .frame(width: 72, alignment: .leading)
                        Spacer()
                        Text(num(cur.min)).frame(width: 48)
                        Text(num(cur.max)).frame(width: 48)
                        Text(num(cur.avg))
                            .font(SomaFont.bold(13))
                            .frame(width: 48)
                        ChangeBadge(
                            current: cur.avg,
                            previous: previous?[keyPath: keyPath].avg,
                            config: config,
                            disabled: false
                        )
                        .frame(minWidth: 64)
                    }
                    .font(SomaFont.regular(13))
                    .foregroundColor(SomaTheme.text)
                    .padding(.vertical, 11)
                    Divider().background(SomaTheme.border)
                }
            }
        }
    }

    private func num(_ v: Double?) -> String {
        guard let v else { return "—" }
        return "\(Int(v.rounded()))"
    }
}

struct ChangeBadge: View {
    let current: Double?
    let previous: Double?
    let config: ChangeConfig
    let disabled: Bool

    var body: some View {
        let type = disabled ? ChangeType.neutral : config.evaluate(current: current, previous: previous)
        let diff = (current ?? 0) - (previous ?? 0)
        HStack(spacing: 2) {
            switch type {
            case .improving:
                Image(systemName: "arrow.down")
                Text("\(absText(diff))")
            case .worsening:
                Image(systemName: "arrow.up")
                Text("\(absText(diff))")
            case .neutral:
                Image(systemName: "minus")
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(color(for: type))
    }

    private func absText(_ diff: Double) -> String {
        "\(Int(abs(diff).rounded()))"
    }

    private func color(for type: ChangeType) -> Color {
        switch type {
        case .improving: return Color(hex: "4ade80")
        case .worsening: return Color(hex: "f87171")
        case .neutral: return SomaTheme.muted
        }
    }
}

struct ReferenceRow: View {
    let label: String
    let value: String
    let sub: String?
    var last: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(SomaFont.bold(13))
                    .foregroundColor(SomaTheme.text)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value)
                        .font(.custom("LINESeedJP-Regular", size: 13))
                        .foregroundColor(SomaTheme.text)
                    if let sub {
                        Text(sub)
                            .font(SomaFont.regular(11))
                            .foregroundColor(SomaTheme.muted)
                    }
                }
            }
            .padding(.vertical, 11)
            if !last { Divider().background(SomaTheme.border) }
        }
    }
}
