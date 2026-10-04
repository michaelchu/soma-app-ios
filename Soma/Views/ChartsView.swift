import SwiftUI
import Charts

// MARK: - Charts tab (mirrors the web ChartsTab: Timeline | Distribution
// switcher, BPTimeChart with MAP / Trend / Markers toggles)

struct ChartsView: View {
    @ObservedObject var store = BPStore.shared
    @EnvironmentObject var filters: FilterState

    @State private var mode: ChartMode = .timeline
    @State private var showMAP = true // web defaults
    @State private var showTrendline = true
    @State private var showMarkers = false

    enum ChartMode: String, CaseIterable, Identifiable {
        case timeline = "Timeline"
        case scatter = "Distribution"
        var id: String { rawValue }
    }

    private var filtered: [BPSession] {
        filterSessions(store.sessions, dateRange: filters.dateRange, timeOfDay: filters.timeOfDay)
            .sorted { $0.date < $1.date } // oldest -> newest for the time axis
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented switcher (mirrors web TabsList)
                Picker("", selection: $mode) {
                    ForEach(ChartMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 60)
                .padding(.top, 8)
                .tint(SomaTheme.rose)

                if filtered.isEmpty {
                    Spacer()
                    Text("No readings yet")
                        .foregroundColor(SomaTheme.muted)
                    Spacer()
                } else if mode == .timeline {
                    TimelineChart(
                        sessions: filtered,
                        showMAP: showMAP,
                        showTrendline: showTrendline,
                        showMarkers: showMarkers
                    )
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                    // Toggle pills (mirror web: MAP / Trend / Markers)
                    HStack(spacing: 8) {
                        FilterPill(label: "MAP", isOn: showMAP) { showMAP.toggle() }
                        FilterPill(label: "Trend", isOn: showTrendline) { showTrendline.toggle() }
                        FilterPill(label: "Markers", isOn: showMarkers) { showMarkers.toggle() }
                    }
                    .padding(.top, 12)
                    Spacer()
                } else {
                    DistributionChart(sessions: filtered)
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                    Text("Each dot is one reading, coloured by category")
                        .font(SomaFont.regular(12))
                        .foregroundColor(SomaTheme.muted)
                        .padding(.top, 8)
                    Spacer()
                }
            }
            .background(SomaTheme.background)
            .navigationTitle("Charts")
        }
        .tint(SomaTheme.rose)
    }
}

// MARK: - Timeline chart (port of BPTimeChart)

struct TimelineChart: View {
    let sessions: [BPSession]
    let showMAP: Bool
    let showTrendline: Bool
    let showMarkers: Bool

    private struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let sys: Int
        let dia: Int
        let map: Int
    }

    private var points: [Point] {
        sessions.compactMap { s in
            guard let d = parseDateOnly(s.date) else { return nil }
            return Point(date: d, sys: s.systolic, dia: s.diastolic, map: s.map)
        }
    }

    /// Linear-regression trendline over systolic (matches web trendline).
    private var trend: [(date: Date, value: Double)] {
        let pts = points
        guard pts.count >= 2 else { return [] }
        let xs = pts.map { $0.date.timeIntervalSince1970 }
        let ys = pts.map { Double($0.sys) }
        let n = Double(pts.count)
        let meanX = xs.reduce(0, +) / n, meanY = ys.reduce(0, +) / n
        let num = zip(xs, ys).map { ($0 - meanX) * ($1 - meanY) }.reduce(0, +)
        let den = xs.map { ($0 - meanX) * ($0 - meanX) }.reduce(0, +)
        guard den != 0 else { return [] }
        let slope = num / den
        let intercept = meanY - slope * meanX
        return pts.map { (date: $0.date, value: slope * $0.date.timeIntervalSince1970 + intercept) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                legendDot(SomaTheme.systolic, "Systolic")
                legendDot(SomaTheme.diastolic, "Diastolic")
            }
            .font(SomaFont.regular(12))
            .foregroundColor(SomaTheme.muted)
            .padding(.horizontal, 6)

            Chart {
                ForEach(points) { p in
                    LineMark(
                        x: .value("Date", p.date),
                        y: .value("Systolic", p.sys)
                    )
                    .foregroundStyle(SomaTheme.systolic)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", p.date),
                        y: .value("Diastolic", p.dia)
                    )
                    .foregroundStyle(SomaTheme.diastolic)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)

                    if showMAP {
                        LineMark(
                            x: .value("Date", p.date),
                            y: .value("MAP", p.map)
                        )
                        .foregroundStyle(SomaTheme.slate)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }

                    if showMarkers {
                        PointMark(x: .value("Date", p.date), y: .value("Systolic", p.sys))
                            .foregroundStyle(SomaTheme.systolic)
                            .symbolSize(30)
                        PointMark(x: .value("Date", p.date), y: .value("Diastolic", p.dia))
                            .foregroundStyle(SomaTheme.diastolic)
                            .symbolSize(30)
                    }
                }

                if showTrendline {
                    ForEach(trend, id: \.date) { t in
                        LineMark(
                            x: .value("Date", t.date),
                            y: .value("Trend", t.value)
                        )
                        .foregroundStyle(SomaTheme.systolic.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(SomaTheme.border)
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(SomaTheme.muted)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(SomaTheme.border)
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(SomaTheme.muted)
                }
            }
            .frame(height: 300)
        }
        .padding(12)
        .background(SomaTheme.card)
        .cornerRadius(SomaTheme.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: SomaTheme.cardRadius)
                .stroke(SomaTheme.border, lineWidth: 1)
        )
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 14, height: 3)
            Text(label)
        }
    }
}

// MARK: - Distribution scatter (port of BPScatterChart)

struct DistributionChart: View {
    let sessions: [BPSession]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart(sessions) { s in
                PointMark(
                    x: .value("Systolic", s.systolic),
                    y: .value("Diastolic", s.diastolic)
                )
                .foregroundStyle(categoryColor(s.category))
                .symbolSize(60)
            }
            .chartXAxis {
                AxisMarks(position: .bottom) { _ in
                    AxisGridLine().foregroundStyle(SomaTheme.border)
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(SomaTheme.muted)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(SomaTheme.border)
                    AxisValueLabel()
                        .font(.system(size: 10))
                        .foregroundStyle(SomaTheme.muted)
                }
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: yDomain)
            .frame(height: 300)

            HStack(spacing: 14) {
                legendDot(SomaTheme.categoryNormalText, "Normal")
                legendDot(SomaTheme.categoryHypertensionText, "Hypertension")
                legendDot(SomaTheme.categoryTreatText, "HTN (Treat)")
            }
            .font(SomaFont.regular(12))
            .foregroundColor(SomaTheme.muted)
            .padding(.horizontal, 6)
        }
        .padding(12)
        .background(SomaTheme.card)
        .cornerRadius(SomaTheme.cardRadius)
        .overlay(
            RoundedRectangle(cornerRadius: SomaTheme.cardRadius)
                .stroke(SomaTheme.border, lineWidth: 1)
        )
    }

    private var xDomain: ClosedRange<Int> {
        let vals = sessions.map(\.systolic)
        guard let lo = vals.min(), let hi = vals.max() else { return 90...140 }
        return (lo - 5)...(hi + 5)
    }

    private var yDomain: ClosedRange<Int> {
        let vals = sessions.map(\.diastolic)
        guard let lo = vals.min(), let hi = vals.max() else { return 60...100 }
        return (lo - 5)...(hi + 5)
    }

    private func categoryColor(_ c: BPCategory) -> Color {
        switch c {
        case .normal: return SomaTheme.categoryNormalText
        case .hypertension: return SomaTheme.categoryHypertensionText
        case .hypertensionTreat: return SomaTheme.categoryTreatText
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
        }
    }
}
