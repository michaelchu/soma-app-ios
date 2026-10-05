import Foundation

// MARK: - Models mirroring the Soma web app's BP domain
// (types/bloodPressure.ts, lib/db/bloodPressure.ts, pages/blood-pressure/utils/bpHelpers.ts,
//  pages/blood-pressure/constants/bpGuidelines.ts — default guideline: HTN Canada 2025)

enum TimeOfDay: String, Codable, CaseIterable, Identifiable, Equatable {
    case morning, afternoon, evening

    var id: String { rawValue }
    var shortLabel: String { rawValue.capitalized }
    /// Matches the web FilterBar labels.
    var fullLabel: String {
        switch self {
        case .morning: return "Morning (6am-12pm)"
        case .afternoon: return "Afternoon (12pm-6pm)"
        case .evening: return "Evening (6pm-12am)"
        }
    }
}

enum Arm: String, Codable {
    case L, R
}

// MARK: - API row (api/blood-pressure.ts serializeRow)

struct BPReadingRow: Codable, Identifiable {
    let id: String
    let sessionId: String
    let date: String // YYYY-MM-DD
    let timeOfDay: TimeOfDay
    let systolic: Int
    let diastolic: Int
    let pulse: Int?
    let notes: String?
    let cuffLocation: String?

    enum CodingKeys: String, CodingKey {
        case id
        case sessionId = "session_id"
        case date = "recorded_date"
        case timeOfDay = "time_of_day"
        case systolic, diastolic, pulse, notes
        case cuffLocation = "cuff_location"
    }
}

struct BPReading: Identifiable {
    let id: String
    let date: String
    let timeOfDay: TimeOfDay
    let systolic: Int
    let diastolic: Int
    let pulse: Int?
    let notes: String?
    let arm: Arm?
}

struct BPSession: Identifiable {
    var id: String { sessionId }
    let sessionId: String
    let date: String // YYYY-MM-DD
    let timeOfDay: TimeOfDay
    let systolic: Int // session average, rounded (matches web calculateSessionAverages)
    let diastolic: Int
    let pulse: Int?
    let notes: String?
    let readings: [BPReading]

    var readingCount: Int { readings.count }
    var pp: Int { systolic - diastolic }
    var map: Int { Int((Double(diastolic) + Double(systolic - diastolic) / 3.0).rounded()) }
    var category: BPCategory { BPCategory.classify(systolic: systolic, diastolic: diastolic) }
}

func arm(from cuffLocation: String?) -> Arm? {
    switch cuffLocation {
    case "left_arm", "left_wrist": return .L
    case "right_arm", "right_wrist": return .R
    default: return nil
    }
}

// MARK: - Session grouping (port of getReadings in lib/db/bloodPressure.ts)

func groupRowsIntoSessions(_ rows: [BPReadingRow]) -> [BPSession] {
    var buckets: [String: [BPReading]] = [:]
    var order: [String] = []
    for row in rows {
        let reading = BPReading(
            id: row.id,
            date: row.date,
            timeOfDay: row.timeOfDay,
            systolic: row.systolic,
            diastolic: row.diastolic,
            pulse: row.pulse,
            notes: row.notes,
            arm: arm(from: row.cuffLocation)
        )
        if buckets[row.sessionId] == nil {
            buckets[row.sessionId] = []
            order.append(row.sessionId)
        }
        buckets[row.sessionId]!.append(reading)
    }

    var sessions: [BPSession] = []
    for sessionId in order {
        guard var readings = buckets[sessionId], !readings.isEmpty else { continue }
        readings.sort { $0.date < $1.date }
        let n = Double(readings.count)
        let avgSys = Int((Double(readings.map(\.systolic).reduce(0, +)) / n).rounded())
        let avgDia = Int((Double(readings.map(\.diastolic).reduce(0, +)) / n).rounded())
        let pulses = readings.compactMap(\.pulse)
        let avgPulse = pulses.isEmpty ? nil : Int((Double(pulses.reduce(0, +)) / Double(pulses.count)).rounded())
        let notes = readings.compactMap(\.notes).filter { !$0.isEmpty }.joined(separator: "\n")
        sessions.append(BPSession(
            sessionId: sessionId,
            date: readings[0].date,
            timeOfDay: readings[0].timeOfDay,
            systolic: avgSys,
            diastolic: avgDia,
            pulse: avgPulse,
            notes: notes.isEmpty ? nil : notes,
            readings: readings
        ))
    }
    // Newest first (matches web sort)
    sessions.sort { $0.date > $1.date }
    return sessions
}

// MARK: - BP categories (HTN Canada 2025 — the web app's DEFAULT_GUIDELINE)

enum BPCategory: CaseIterable, Equatable {
    case normal
    case hypertension // "Hypertension"
    case hypertensionTreat // "HTN (Treat)"

    /// Port of getBPCategory (bpHelpers.ts) for the default guideline.
    static func classify(systolic: Int, diastolic: Int) -> BPCategory {
        // Checked most-severe first, matching the web loop.
        if systolic >= 140 || diastolic >= 90 { return .hypertensionTreat }
        if systolic >= 130 || diastolic >= 80 { return .hypertension }
        return .normal // both <= 129 / <= 79
    }

    var label: String {
        switch self {
        case .normal: return "Normal"
        case .hypertension: return "Hypertension"
        case .hypertensionTreat: return "HTN (Treat)"
        }
    }

    var shortLabel: String {
        switch self {
        case .normal: return "Normal"
        case .hypertension: return "HTN"
        case .hypertensionTreat: return "HTN (Treat)"
        }
    }
}

// MARK: - Statistics (port of calculateFullStats in bpHelpers.ts)

struct StatValues {
    let min: Double?
    let max: Double?
    let avg: Double?
}

struct FullStats {
    let systolic: StatValues
    let diastolic: StatValues
    let pulse: StatValues
    let pp: StatValues
    let map: StatValues
    let count: Int
}

func calcStats(_ values: [Double]) -> StatValues {
    guard !values.isEmpty else { return StatValues(min: nil, max: nil, avg: nil) }
    return StatValues(
        min: values.min(),
        max: values.max(),
        avg: values.reduce(0, +) / Double(values.count)
    )
}

/// Operates on sessions (session averages), exactly like the web StatisticsTab,
/// which receives the filtered session list.
func calculateFullStats(sessions: [BPSession]) -> FullStats? {
    guard !sessions.isEmpty else { return nil }
    let systolics = sessions.map { Double($0.systolic) }
    let diastolics = sessions.map { Double($0.diastolic) }
    let pulses = sessions.compactMap { $0.pulse }.map { Double($0) }
    let pps = sessions.map { Double($0.systolic - $0.diastolic) }
    // MAP = diastolic + PP/3, full precision (matches web)
    let maps = sessions.map { Double($0.diastolic) + Double($0.systolic - $0.diastolic) / 3.0 }
    return FullStats(
        systolic: calcStats(systolics),
        diastolic: calcStats(diastolics),
        pulse: calcStats(pulses),
        pp: calcStats(pps),
        map: calcStats(maps),
        count: sessions.count
    )
}

// MARK: - Date ranges (port of DateRangeTabs + dateUtils)

enum DateRange: String, CaseIterable, Identifiable {
    case month = "1m"
    case quarter = "3m"
    case halfYear = "6m"
    case year = "1y"
    case all = "all"
    case custom = "custom"

    static let presets: [DateRange] = [.month, .quarter, .halfYear, .year, .all]

    var id: String { rawValue }

    var label: String {
        switch self {
        case .month: return "1M"
        case .quarter: return "3M"
        case .halfYear: return "6M"
        case .year: return "1Y"
        case .all: return "All"
        case .custom: return "Custom"
        }
    }

    /// Start of the current period (matches calculatePeriodStart).
    func startDate(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .month:
            let d = calendar.date(byAdding: .month, value: -1, to: now)!
            return calendar.startOfDay(for: d)
        case .quarter:
            let d = calendar.date(byAdding: .month, value: -3, to: now)!
            return calendar.startOfDay(for: d)
        case .halfYear:
            let d = calendar.date(byAdding: .month, value: -6, to: now)!
            return calendar.startOfDay(for: d)
        case .year:
            let d = calendar.date(byAdding: .year, value: -1, to: now)!
            return calendar.startOfDay(for: d)
        case .all, .custom:
            return nil
        }
    }

    /// Previous equivalent period (matches getPreviousDateRange).
    func previousPeriod(now: Date = Date(), calendar: Calendar = .current) -> (start: Date, end: Date)? {
        guard let start = startDate(now: now, calendar: calendar) else { return nil }
        let (component, value): (Calendar.Component, Int) = {
            switch self {
            case .month: return (.month, -1)
            case .quarter: return (.month, -3)
            case .halfYear: return (.month, -6)
            case .year: return (.year, -1)
            case .all, .custom: return (.day, 0)
            }
        }()
        guard let prevStart = calendar.date(byAdding: component, value: value, to: start) else { return nil }
        return (prevStart, start)
    }
}

/// Parse a YYYY-MM-DD string as a local date (matches web parseDateOnly —
/// avoids UTC-midnight shifting the reading into the previous day).
func parseDateOnly(_ s: String, calendar: Calendar = .current) -> Date? {
    let parts = s.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    var comps = DateComponents()
    comps.year = parts[0]; comps.month = parts[1]; comps.day = parts[2]
    guard let date = calendar.date(from: comps) else { return nil }
    let resolved = calendar.dateComponents([.year, .month, .day], from: date)
    guard resolved.year == comps.year,
          resolved.month == comps.month,
          resolved.day == comps.day else { return nil }
    return date
}

func isValidBloodPressureInput(systolic: String, diastolic: String, pulse: String) -> Bool {
    guard let systolicValue = Int(systolic),
          let diastolicValue = Int(diastolic),
          (40...300).contains(systolicValue),
          (30...200).contains(diastolicValue) else { return false }
    return pulse.isEmpty || Int(pulse).map { (30...250).contains($0) } == true
}

/// Port of filterReadings (FilterBar.tsx).
func filterSessions(
    _ sessions: [BPSession],
    dateRange: DateRange,
    timeOfDay: TimeOfDay?,
    customStartDate: Date? = nil,
    customEndDate: Date? = nil,
    calendar: Calendar = .current
) -> [BPSession] {
    var filtered = sessions

    if dateRange == .custom, let customStartDate, let customEndDate {
        let start = calendar.startOfDay(for: min(customStartDate, customEndDate))
        let end = calendar.startOfDay(for: max(customStartDate, customEndDate))
        filtered = filtered.filter { session in
            guard let date = parseDateOnly(session.date, calendar: calendar) else { return false }
            return date >= start && date <= end
        }
    } else if let start = dateRange.startDate(calendar: calendar) {
        filtered = filtered.filter { session in
            guard let date = parseDateOnly(session.date, calendar: calendar) else { return false }
            return date >= start
        }
    }

    if let timeOfDay {
        filtered = filtered.filter { $0.timeOfDay == timeOfDay }
    }
    return filtered
}

// MARK: - Change indicator (port of getChangeType in ChangeIndicator.tsx)

enum ChangeType: Equatable {
    case improving
    case worsening
    case neutral
}

enum ChangeConfig {
    /// Lower is better; neutral when both are within the optimal range.
    case lowerIsBetter(optimalMax: Double)
    /// Closer to midpoint is better; neutral when both are inside the buffer zone.
    case midpoint(mid: Double, bufferMin: Double, bufferMax: Double)

    func evaluate(current: Double?, previous: Double?) -> ChangeType {
        guard let current, let previous else { return .neutral }
        switch self {
        case .lowerIsBetter(let optimalMax):
            if current <= optimalMax && previous <= optimalMax { return .neutral }
            if current < previous { return .improving }
            if current > previous { return .worsening }
            return .neutral
        case .midpoint(let mid, let bufMin, let bufMax):
            let curIn = current >= bufMin && current <= bufMax
            let prevIn = previous >= bufMin && previous <= bufMax
            if curIn && prevIn { return .neutral }
            let curDist = abs(current - mid)
            let prevDist = abs(previous - mid)
            if curDist < prevDist { return .improving }
            if curDist > prevDist { return .worsening }
            return .neutral
        }
    }
}

// MARK: - Display helpers (port of bpHelpers formatBPDateTime / dateUtils)

/// "Sep 24" style date + "Morning" style time label, hiding the current year
/// (matches formatBPDateTime with hideCurrentYear).
func formatSessionDate(_ dateString: String) -> String {
    guard let date = parseDateOnly(dateString) else { return dateString }
    let f = DateFormatter()
    f.dateFormat = "MMM d"
    return f.string(from: date)
}

/// "Thursday, Sep 24" style header for the timeline (matches web formatRelativeDate).
func formatTimelineHeader(_ dateString: String, now: Date = Date(), calendar: Calendar = .current) -> String {
    guard let date = parseDateOnly(dateString) else { return dateString }
    if calendar.isDate(date, inSameDayAs: now) { return "Today" }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
       calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
    let f = DateFormatter()
    f.dateFormat = "EEEE, MMM d"
    return f.string(from: date)
}

/// "Sep 23, 2024 - Sep 24, 2026" style range label (matches StatisticsTab).
func formatDateRangeLabel(sessions: [BPSession]) -> String {
    let dates = sessions.compactMap { parseDateOnly($0.date) }.sorted()
    guard let first = dates.first, let last = dates.last else { return "" }
    let f = DateFormatter()
    f.dateFormat = "MMM d, yyyy"
    return "\(f.string(from: first)) - \(f.string(from: last))"
}
