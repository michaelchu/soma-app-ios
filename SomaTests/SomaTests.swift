import XCTest
@testable import Soma

// MARK: - Unit tests for the ported BP domain logic (BPModels.swift).
// Run in Xcode with Cmd+U. These mirror the web app's tested behavior
// (bpHelpers.ts, bpGuidelines.ts, dateUtils.ts).

final class BPCategoryTests: XCTestCase {
    func testNormal() {
        XCTAssertEqual(BPCategory.classify(systolic: 116, diastolic: 79), .normal)
        XCTAssertEqual(BPCategory.classify(systolic: 129, diastolic: 79), .normal)
    }

    func testHypertensionBoundaries() {
        // HTN Canada 2025: systolic >= 130 OR diastolic >= 80
        XCTAssertEqual(BPCategory.classify(systolic: 130, diastolic: 79), .hypertension)
        XCTAssertEqual(BPCategory.classify(systolic: 129, diastolic: 80), .hypertension)
        XCTAssertEqual(BPCategory.classify(systolic: 135, diastolic: 85), .hypertension)
    }

    func testTreatBoundaries() {
        // systolic >= 140 OR diastolic >= 90 (checked most-severe first)
        XCTAssertEqual(BPCategory.classify(systolic: 140, diastolic: 79), .hypertensionTreat)
        XCTAssertEqual(BPCategory.classify(systolic: 129, diastolic: 90), .hypertensionTreat)
        XCTAssertEqual(BPCategory.classify(systolic: 150, diastolic: 95), .hypertensionTreat)
    }

    func testLabels() {
        XCTAssertEqual(BPCategory.normal.label, "Normal")
        XCTAssertEqual(BPCategory.hypertension.label, "Hypertension")
        XCTAssertEqual(BPCategory.hypertensionTreat.label, "HTN (Treat)")
    }
}

final class BPSessionMathTests: XCTestCase {
    func testPulsePressure() {
        let s = makeSession(sys: 120, dia: 80)
        XCTAssertEqual(s.pp, 40)
    }

    func testMAP() {
        // MAP = diastolic + PP/3, rounded (matches web)
        let s = makeSession(sys: 120, dia: 80)
        XCTAssertEqual(s.map, 93) // 80 + 40/3 = 93.33
        let s2 = makeSession(sys: 131, dia: 84)
        XCTAssertEqual(s2.map, 100) // 84 + 47/3 = 99.67
    }
}

final class SessionGroupingTests: XCTestCase {
    func testGroupsRowsBySessionId() {
        let rows = [
            makeRow(id: "r1", session: "s1", sys: 120, dia: 80),
            makeRow(id: "r2", session: "s1", sys: 122, dia: 82),
            makeRow(id: "r3", session: "s2", sys: 118, dia: 78),
        ]
        let sessions = groupRowsIntoSessions(rows)
        XCTAssertEqual(sessions.count, 2)
    }

    func testAveragesReadings() {
        // Matches web calculateSessionAverages (rounded)
        let rows = [
            makeRow(id: "r1", session: "s1", sys: 120, dia: 80, pulse: 70),
            makeRow(id: "r2", session: "s1", sys: 123, dia: 83, pulse: 72),
        ]
        let sessions = groupRowsIntoSessions(rows)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].systolic, 122) // (120+123)/2 = 121.5 -> 122
        XCTAssertEqual(sessions[0].diastolic, 82) // (80+83)/2 = 81.5 -> 82
        XCTAssertEqual(sessions[0].pulse, 71)
        XCTAssertEqual(sessions[0].readingCount, 2)
    }

    func testJoinsNotes() {
        let rows = [
            makeRow(id: "r1", session: "s1", sys: 120, dia: 80, notes: "first"),
            makeRow(id: "r2", session: "s1", sys: 122, dia: 82, notes: "second"),
        ]
        let sessions = groupRowsIntoSessions(rows)
        XCTAssertEqual(sessions[0].notes, "first\nsecond")
    }

    func testSortsNewestFirst() {
        let rows = [
            makeRow(id: "r1", session: "s1", sys: 120, dia: 80, date: "2026-09-20"),
            makeRow(id: "r2", session: "s2", sys: 122, dia: 82, date: "2026-09-24"),
        ]
        let sessions = groupRowsIntoSessions(rows)
        XCTAssertEqual(sessions[0].date, "2026-09-24")
        XCTAssertEqual(sessions[1].date, "2026-09-20")
    }

    func testEmptyPulse() {
        let rows = [makeRow(id: "r1", session: "s1", sys: 120, dia: 80, pulse: nil)]
        let sessions = groupRowsIntoSessions(rows)
        XCTAssertNil(sessions[0].pulse)
    }
}

final class StatisticsTests: XCTestCase {
    func testFullStats() {
        let sessions = [
            makeSession(sys: 120, dia: 80, pulse: 70),
            makeSession(sys: 130, dia: 90, pulse: 80),
        ]
        let stats = calculateFullStats(sessions: sessions)!
        XCTAssertEqual(stats.count, 2)
        XCTAssertEqual(stats.systolic.min!, 120, accuracy: 0.001)
        XCTAssertEqual(stats.systolic.max!, 130, accuracy: 0.001)
        XCTAssertEqual(stats.systolic.avg!, 125, accuracy: 0.001)
        XCTAssertEqual(stats.diastolic.avg!, 85, accuracy: 0.001)
        XCTAssertEqual(stats.pulse.avg!, 75, accuracy: 0.001)
        // PP: 40, 40
        XCTAssertEqual(stats.pp.avg!, 40, accuracy: 0.001)
        // MAP full precision: (80 + 40/3 + 90 + 40/3) / 2 = 98.333
        XCTAssertEqual(stats.map.avg!, 98.333, accuracy: 0.01)
    }

    func testEmptyReturnsNil() {
        XCTAssertNil(calculateFullStats(sessions: []))
    }

    func testPulseNilWhenNoData() {
        let sessions = [makeSession(sys: 120, dia: 80, pulse: nil)]
        let stats = calculateFullStats(sessions: sessions)!
        XCTAssertNil(stats.pulse.avg)
        XCTAssertNotNil(stats.systolic.avg)
    }
}

final class DateRangeTests: XCTestCase {
    func testWeekStartsSixDaysAgo() {
        let cal = Calendar.current
        let now = Date()
        let start = DateRange.week.startDate(now: now, calendar: cal)!
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: start), to: cal.startOfDay(for: now)).day!
        XCTAssertEqual(days, 6)
    }

    func testAllHasNoStartOrPrevious() {
        XCTAssertNil(DateRange.all.startDate())
        XCTAssertNil(DateRange.all.previousPeriod())
    }

    func testPreviousPeriodLength() {
        // Previous week should be the 7 days before the current week
        let cal = Calendar.current
        let now = Date()
        let period = DateRange.week.previousPeriod(now: now, calendar: cal)!
        let days = cal.dateComponents([.day], from: period.start, to: period.end).day!
        XCTAssertEqual(days, 7)
    }
}

final class FilterTests: XCTestCase {
    func testFiltersByTimeOfDay() {
        let sessions = [
            makeSession(sys: 120, dia: 80, tod: .morning),
            makeSession(sys: 122, dia: 82, tod: .evening),
        ]
        let filtered = filterSessions(sessions, dateRange: .all, timeOfDay: .morning)
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].timeOfDay, .morning)
    }

    func testAllRangeKeepsEverything() {
        let sessions = [
            makeSession(sys: 120, dia: 80, date: "2024-09-24"),
            makeSession(sys: 122, dia: 82, date: "2026-09-24"),
        ]
        XCTAssertEqual(filterSessions(sessions, dateRange: .all, timeOfDay: nil).count, 2)
    }
}

final class ChangeConfigTests: XCTestCase {
    func testLowerIsBetter() {
        let config = ChangeConfig.lowerIsBetter(optimalMax: 130)
        XCTAssertEqual(config.evaluate(current: 120, previous: 135), .improving)
        XCTAssertEqual(config.evaluate(current: 135, previous: 120), .worsening)
        // Both in optimal range -> neutral
        XCTAssertEqual(config.evaluate(current: 120, previous: 125), .neutral)
        XCTAssertEqual(config.evaluate(current: 125, previous: 125), .neutral)
    }

    func testMidpoint() {
        let config = ChangeConfig.midpoint(mid: 80, bufferMin: 70, bufferMax: 90)
        // Both in buffer -> neutral
        XCTAssertEqual(config.evaluate(current: 75, previous: 85), .neutral)
        // Moving toward midpoint -> improving
        XCTAssertEqual(config.evaluate(current: 85, previous: 100), .improving)
        // Moving away -> worsening
        XCTAssertEqual(config.evaluate(current: 100, previous: 85), .worsening)
    }

    func testNilIsNeutral() {
        let config = ChangeConfig.lowerIsBetter(optimalMax: 130)
        XCTAssertEqual(config.evaluate(current: nil, previous: 135), .neutral)
        XCTAssertEqual(config.evaluate(current: 120, previous: nil), .neutral)
    }
}

final class DateFormatTests: XCTestCase {
    func testParseDateOnly() {
        let cal = Calendar.current
        let d = parseDateOnly("2026-09-24", calendar: cal)!
        let comps = cal.dateComponents([.year, .month, .day], from: d)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 9)
        XCTAssertEqual(comps.day, 24)
        XCTAssertNil(parseDateOnly("not-a-date"))
        XCTAssertNil(parseDateOnly("2026-02-31"))
    }

    func testFormatSessionDate() {
        // "Sep 24" style, no year
        XCTAssertEqual(formatSessionDate("2026-09-24"), "Sep 24")
    }

    func testFormatTimelineHeader() {
        let cal = Calendar.current
        let now = Date()
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        XCTAssertEqual(formatTimelineHeader(df.string(from: now)), "Today")
        let yesterday = cal.date(byAdding: .day, value: -1, to: now)!
        XCTAssertEqual(formatTimelineHeader(df.string(from: yesterday)), "Yesterday")
    }
}

final class ReadingInputValidationTests: XCTestCase {
    func testAcceptsBoundaryValuesAndOptionalPulse() {
        XCTAssertTrue(isValidBloodPressureInput(systolic: "40", diastolic: "30", pulse: ""))
        XCTAssertTrue(isValidBloodPressureInput(systolic: "300", diastolic: "200", pulse: "30"))
        XCTAssertTrue(isValidBloodPressureInput(systolic: "120", diastolic: "80", pulse: "250"))
    }

    func testRejectsInvalidValues() {
        XCTAssertFalse(isValidBloodPressureInput(systolic: "39", diastolic: "80", pulse: "70"))
        XCTAssertFalse(isValidBloodPressureInput(systolic: "120", diastolic: "201", pulse: "70"))
        XCTAssertFalse(isValidBloodPressureInput(systolic: "120", diastolic: "80", pulse: "29"))
        XCTAssertFalse(isValidBloodPressureInput(systolic: "120", diastolic: "80", pulse: "251"))
        XCTAssertFalse(isValidBloodPressureInput(systolic: "120", diastolic: "80", pulse: "invalid"))
    }
}

@MainActor
final class BPStoreTests: XCTestCase {
    func testLoadMapsHealthSamplesDirectlyToSessions() async {
        let health = FakeHealthKitManager(samples: [
            makeHealthSample(id: "morning", timeOfDay: .morning),
            makeHealthSample(id: "evening", timeOfDay: .evening)
        ])
        let store = BPStore(healthKit: health)

        await store.load()

        XCTAssertEqual(store.sessions.map(\.sessionId), ["morning", "evening"])
        XCTAssertEqual(store.sessions.map(\.timeOfDay), [.morning, .evening])
        XCTAssertNil(store.errorMessage)
    }

    func testDeleteRemovesHealthKitSample() async {
        let health = FakeHealthKitManager(samples: [makeHealthSample(id: "sample-1")])
        let store = BPStore(healthKit: health)
        await store.load()

        await store.deleteSession(store.sessions[0])

        XCTAssertEqual(health.deletedIDs, ["sample-1"])
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testFailedDeleteRestoresState() async {
        let health = FakeHealthKitManager(samples: [makeHealthSample(id: "sample-1")])
        health.deleteError = TestFailure.expected
        let store = BPStore(healthKit: health)
        await store.load()

        await store.deleteSession(store.sessions[0])

        XCTAssertEqual(store.sessions.map(\.sessionId), ["sample-1"])
        XCTAssertNotNil(store.errorMessage)
    }

    func testFailedRefreshPreservesPreviouslyLoadedSessionsAndClearsLoading() async {
        let health = FakeHealthKitManager(samples: [makeHealthSample(id: "sample-1")])
        let store = BPStore(healthKit: health)
        await store.load()
        health.fetchError = TestFailure.expected

        await store.load()

        XCTAssertEqual(store.sessions.map(\.sessionId), ["sample-1"])
        XCTAssertFalse(store.isLoading)
        XCTAssertNotNil(store.errorMessage)
    }

    func testLoadPreservesHealthMetadata() async {
        let health = FakeHealthKitManager(samples: [
            makeHealthSample(notes: "After exercise", arm: .L)
        ])
        let store = BPStore(healthKit: health)

        await store.load()

        XCTAssertEqual(store.sessions[0].notes, "After exercise")
        XCTAssertEqual(store.sessions[0].readings[0].notes, "After exercise")
        XCTAssertEqual(store.sessions[0].readings[0].arm, .L)
    }

    func testAddSessionPassesNotesAndArmToHealthKit() async {
        let health = FakeHealthKitManager()
        let store = BPStore(healthKit: health)

        let saved = await store.addSession(
            date: Date(timeIntervalSince1970: 1_790_208_000),
            timeOfDay: .morning,
            systolic: 120,
            diastolic: 80,
            pulse: 70,
            arm: .R,
            notes: "  Before breakfast  "
        )

        XCTAssertTrue(saved)
        XCTAssertEqual(health.savedReadings.count, 1)
        XCTAssertEqual(health.savedReadings[0].notes, "Before breakfast")
        XCTAssertEqual(health.savedReadings[0].arm, .R)
    }
}

// MARK: - Test helpers

private var testCounter = 0

private func makeSession(sys: Int, dia: Int, pulse: Int? = nil, date: String = "2026-09-24", tod: TimeOfDay = .morning) -> BPSession {
    testCounter += 1
    return BPSession(
        sessionId: "test-\(testCounter)",
        date: date,
        timeOfDay: tod,
        systolic: sys,
        diastolic: dia,
        pulse: pulse,
        notes: nil,
        readings: []
    )
}

private func makeRow(id: String, session: String, sys: Int, dia: Int, pulse: Int? = nil, date: String = "2026-09-24", notes: String? = nil) -> BPReadingRow {
    BPReadingRow(
        id: id,
        sessionId: session,
        date: date,
        timeOfDay: .morning,
        systolic: sys,
        diastolic: dia,
        pulse: pulse,
        notes: notes,
        cuffLocation: nil
    )
}

private func makeHealthSample(
    id: String = UUID().uuidString,
    timeOfDay: TimeOfDay = .morning,
    notes: String? = nil,
    arm: Arm? = nil
) -> HealthSampleReading {
    HealthSampleReading(
        id: id,
        date: Date(timeIntervalSince1970: 1_790_208_000),
        dateString: "2026-09-24",
        timeOfDay: timeOfDay,
        systolic: 120,
        diastolic: 80,
        pulse: 70,
        notes: notes,
        arm: arm
    )
}

private enum TestFailure: Error {
    case expected
}

private final class FakeAPIClient: SomaAPIClientProtocol {
    var isConfigured = true
    var rows: [BPReadingRow]
    var fetchError: Error?
    var createError: Error?
    var deleteError: Error?
    private(set) var createdSessions: [(date: String, timeOfDay: TimeOfDay)] = []

    init(rows: [BPReadingRow] = []) {
        self.rows = rows
    }

    func fetchBloodPressureRows() async throws -> [BPReadingRow] {
        if let fetchError { throw fetchError }
        return rows
    }

    func createSession(
        date: String,
        timeOfDay: TimeOfDay,
        readings: [SomaAPIClient.NewReading],
        notes: String?
    ) async throws -> String {
        if let createError { throw createError }
        createdSessions.append((date, timeOfDay))
        return "created-\(createdSessions.count)"
    }

    func deleteSession(sessionId: String) async throws {
        if let deleteError { throw deleteError }
    }
}

private final class FakeHealthKitManager: HealthKitManagerProtocol {
    struct SavedReading {
        let notes: String?
        let arm: Arm?
    }

    var samples: [HealthSampleReading]
    var fetchError: Error?
    var saveError: Error?
    var deleteError: Error?
    private(set) var deletedIDs: [String] = []
    private(set) var savedReadings: [SavedReading] = []

    init(samples: [HealthSampleReading] = []) {
        self.samples = samples
    }

    func saveReading(
        systolic: Int,
        diastolic: Int,
        pulse: Int?,
        date: Date,
        syncIdentifier: String?,
        notes: String?,
        arm: Arm?
    ) async throws {
        if let saveError { throw saveError }
        savedReadings.append(SavedReading(notes: notes, arm: arm))
    }

    func fetchBloodPressureSamples(daysBack: Int) async throws -> [HealthSampleReading] {
        if let fetchError { throw fetchError }
        return samples
    }

    func deleteBloodPressureSample(id: String) async throws {
        if let deleteError { throw deleteError }
        deletedIDs.append(id)
        samples.removeAll { $0.id == id }
    }

    func deleteAllSomaHealthSamples() async throws -> Int {
        if let deleteError { throw deleteError }
        let count = samples.count
        samples.removeAll()
        return count
    }
}
