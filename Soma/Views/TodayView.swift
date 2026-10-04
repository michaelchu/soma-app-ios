import SwiftUI

// MARK: - Today tab (mirrors the Soma web home page: metric card, 30-day bars,
// bulleted Insights, Recent Activity timeline — plus the v1 reminder toggle)

struct TodayView: View {
    @ObservedObject var store = BPStore.shared
    @ObservedObject var reminders = ReminderManager.shared
    @Binding var showQuickLog: Bool
    @Binding var showSettings: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // BP metric card (mirrors MainPage MetricCard: value+unit, icon, uppercase label)
                    if let latest = store.sessions.first {
                        Button {
                            // Tapping the card could open Readings; keep it simple for v1
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("\(latest.systolic)/\(latest.diastolic)")
                                        .font(SomaFont.bold(26))
                                        .foregroundColor(SomaTheme.text)
                                    + Text(" mmHg")
                                        .font(SomaFont.regular(14))
                                        .foregroundColor(SomaTheme.muted)
                                    Spacer()
                                    Image(systemName: "waveform.path.ecg")
                                        .foregroundColor(SomaTheme.systolic)
                                        .font(.title3)
                                }
                                Text("Blood pressure")
                                    .font(SomaFont.regular(11))
                                    .foregroundColor(SomaTheme.muted)
                                    .textCase(.uppercase)
                                    .tracking(1)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                LinearGradient(
                                    colors: [SomaTheme.rose.opacity(0.20), SomaTheme.rose.opacity(0.05), .clear],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: SomaTheme.cardRadius)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                            .cornerRadius(SomaTheme.cardRadius)
                        }
                        .buttonStyle(.plain)
                    }

                    // Last 30 days — daily average diastolic bars
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Avg diastolic · last 30 days")
                            .font(SomaFont.regular(13))
                            .foregroundColor(SomaTheme.muted)
                        ThirtyDayBars(sessions: store.sessions)
                            .frame(height: 96)
                    }
                    .padding(14)
                    .background(SomaTheme.card)
                    .cornerRadius(SomaTheme.cardRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: SomaTheme.cardRadius)
                            .stroke(SomaTheme.border, lineWidth: 1)
                    )
                    .padding(.top, 12)

                    // Insights (bulleted, top 3 — same strings as the web Insights component)
                    Text("Insights")
                        .font(SomaFont.bold(12))
                        .foregroundColor(SomaTheme.muted)
                        .textCase(.uppercase)
                        .tracking(1)
                        .padding(.top, 22)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(bpInsights(sessions: store.sessions), id: \.self) { insight in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•").foregroundColor(SomaTheme.muted)
                                Text(insight)
                                    .font(SomaFont.regular(14))
                                    .foregroundColor(SomaTheme.text)
                            }
                        }
                    }
                    .padding(.top, 8)

                    // Daily reminder (the v1 addition)
                    HStack(spacing: 12) {
                        Image(systemName: "bell")
                            .foregroundColor(SomaTheme.rose)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Daily reminder")
                                .font(SomaFont.bold(14))
                                .foregroundColor(SomaTheme.text)
                            Text("\(reminders.timeLabel) · measure before coffee")
                                .font(SomaFont.regular(12))
                                .foregroundColor(SomaTheme.muted)
                        }
                        Spacer()
                        Toggle("", isOn: $reminders.isEnabled)
                            .tint(SomaTheme.rose)
                            .onChange(of: reminders.isEnabled) { _, on in
                                if on {
                                    Task { _ = await reminders.requestPermission() }
                                }
                            }
                    }
                    .padding(14)
                    .background(SomaTheme.card)
                    .cornerRadius(SomaTheme.cardRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: SomaTheme.cardRadius)
                            .stroke(SomaTheme.border, lineWidth: 1)
                    )
                    .padding(.top, 14)

                    // Recent Activity (mirrors web Timeline: 30 days, date headers)
                    Text("Recent Activity")
                        .font(SomaFont.bold(12))
                        .foregroundColor(SomaTheme.muted)
                        .textCase(.uppercase)
                        .tracking(1)
                        .padding(.top, 22)
                    RecentActivityTimeline(sessions: store.sessions)
                        .padding(.top, 8)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 18)
            }
            .background(SomaTheme.background)
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .tint(SomaTheme.rose)
    }
}

// MARK: - Insights (port of Insights.tsx BP logic)

func bpInsights(sessions: [BPSession]) -> [String] {
    var insights: [String] = []
    guard !sessions.isEmpty else {
        return ["Keep tracking to get personalized insights about your health patterns."]
    }

    // Trend: linear regression of diastolic over the last 60 days -> points/month.
    // (Web: trendModifier > 0 means trending down.)
    let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date())!
    let recent = sessions.filter { (parseDateOnly($0.date) ?? .distantPast) >= cutoff }
        .sorted { $0.date < $1.date }
    if recent.count >= 5 {
        let xs = recent.compactMap { parseDateOnly($0.date)?.timeIntervalSince1970 }
        let ys = recent.map { Double($0.diastolic) }
        let slope = linearSlope(xs: xs, ys: ys) // diastolic points per second
        let pointsPerMonth = -slope * 30 * 24 * 3600
        if pointsPerMonth > 0.5 {
            insights.append("BP is trending down by \(Int(pointsPerMonth.rounded())) points - good progress!")
        } else if pointsPerMonth < -0.5 {
            insights.append("BP has been trending up recently. Monitor and consider lifestyle adjustments.")
        }
    }

    // Variability: SD of diastolic (web: variabilityPenalty > 10)
    let dias = sessions.map { Double($0.diastolic) }
    if dias.count >= 5, standardDeviation(dias) > 8 {
        insights.append("Your BP readings show high variability. Try measuring at consistent times.")
    }

    // v1 has no activity data (web: confidenceFactor < 1 nudge)
    insights.append("Add activity data to get a more complete health picture.")

    let shown = Array(insights.prefix(3))
    return shown.isEmpty
        ? ["Keep tracking to get personalized insights about your health patterns."]
        : shown
}

private func linearSlope(xs: [Double], ys: [Double]) -> Double {
    let n = Double(xs.count)
    let meanX = xs.reduce(0, +) / n, meanY = ys.reduce(0, +) / n
    let num = zip(xs, ys).map { ($0 - meanX) * ($1 - meanY) }.reduce(0, +)
    let den = xs.map { ($0 - meanX) * ($0 - meanX) }.reduce(0, +)
    return den == 0 ? 0 : num / den
}

private func standardDeviation(_ values: [Double]) -> Double {
    guard values.count > 1 else { return 0 }
    let mean = values.reduce(0, +) / Double(values.count)
    let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
    return variance.squareRoot()
}

// MARK: - 30-day bars

struct ThirtyDayBars: View {
    let sessions: [BPSession]

    /// Daily average diastolic for the last 30 days (oldest -> newest).
    private var dailyAverages: [Double?] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<30).map { back in
            let day = cal.date(byAdding: .day, value: -back, to: today)!
            let days = sessions.filter {
                guard let d = parseDateOnly($0.date) else { return false }
                return cal.isDate(d, inSameDayAs: day)
            }
            guard !days.isEmpty else { return nil }
            return days.map { Double($0.diastolic) }.reduce(0, +) / Double(days.count)
        }.reversed()
    }

    var body: some View {
        let values = dailyAverages
        let maxV = (values.compactMap { $0 }.max() ?? 100)
        let minV = (values.compactMap { $0 }.min() ?? 60)
        let span = max(maxV - minV, 1)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<30, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [SomaTheme.systolic, SomaTheme.rose.opacity(0.55)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: values[i].map { 12 + 84 * CGFloat(($0 - minV) / span) } ?? 6)
                    .opacity(values[i] == nil ? 0.25 : 1)
            }
        }
    }
}

// MARK: - Recent activity timeline (port of Timeline.tsx)

struct RecentActivityTimeline: View {
    let sessions: [BPSession]

    private var grouped: [(date: String, sessions: [BPSession])] {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: Date()))!
        var buckets: [String: [BPSession]] = [:]
        for s in sessions {
            guard let d = parseDateOnly(s.date), d >= cutoff else { continue }
            buckets[s.date, default: []].append(s)
        }
        return buckets.keys.sorted(by: >).map { (date: $0, sessions: buckets[$0]!.sorted { $0.date > $1.date }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(grouped, id: \.date) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(SomaTheme.text)
                            .frame(width: 11, height: 11)
                        Text(formatTimelineHeader(group.date))
                            .font(SomaFont.medium(13))
                            .foregroundColor(SomaTheme.text)
                    }
                    ForEach(group.sessions) { s in
                        HStack {
                            Image(systemName: "waveform.path.ecg")
                                .foregroundColor(SomaTheme.systolic)
                                .font(.caption)
                            Text("BP: \(s.systolic)/\(s.diastolic)")
                                .font(SomaFont.regular(13))
                                .foregroundColor(SomaTheme.text)
                            Spacer()
                            Text(s.timeOfDay.shortLabel)
                                .font(SomaFont.regular(11))
                                .foregroundColor(SomaTheme.muted)
                        }
                        .padding(.leading, 26)
                    }
                }
            }
        }
        .overlay(alignment: .leading) {
            // Vertical timeline line
            Rectangle()
                .fill(SomaTheme.border)
                .frame(width: 1)
                .padding(.leading, 5)
                .padding(.vertical, 8)
        }
    }
}
