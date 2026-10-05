import Foundation
import SwiftUI

protocol SomaAPIClientProtocol {
    var isConfigured: Bool { get }
    func fetchBloodPressureRows() async throws -> [BPReadingRow]
    func createSession(
        date: String,
        timeOfDay: TimeOfDay,
        readings: [SomaAPIClient.NewReading],
        notes: String?
    ) async throws -> String
    func deleteSession(sessionId: String) async throws
}

protocol HealthKitManagerProtocol {
    func saveReading(
        systolic: Int,
        diastolic: Int,
        pulse: Int?,
        date: Date,
        syncIdentifier: String?,
        notes: String?,
        arm: Arm?
    ) async throws
    func fetchBloodPressureSamples(daysBack: Int) async throws -> [HealthSampleReading]
    func deleteBloodPressureSample(id: String) async throws
    func deleteAllSomaHealthSamples() async throws -> Int
}

extension SomaAPIClient: SomaAPIClientProtocol {}
extension HealthKitManager: HealthKitManagerProtocol {}

// MARK: - Apple Health-backed blood pressure state

@MainActor
final class BPStore: ObservableObject {
    static let shared = BPStore()

    @Published private(set) var sessions: [BPSession] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let api: any SomaAPIClientProtocol
    private let healthKit: any HealthKitManagerProtocol

    // Vercel is retained only for the one-time HealthKit migration repair.
    init(
        api: any SomaAPIClientProtocol = SomaAPIClient.shared,
        healthKit: any HealthKitManagerProtocol = HealthKitManager.shared,
        defaults: UserDefaults = .standard
    ) {
        self.api = api
        _ = defaults
        self.healthKit = healthKit
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let samples = try await healthKit.fetchBloodPressureSamples(daysBack: 3650)
            sessions = samples.map(Self.session(from:))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func addSession(
        date: Date,
        timeOfDay: TimeOfDay,
        systolic: Int,
        diastolic: Int,
        pulse: Int?,
        arm: Arm?,
        notes: String?
    ) async -> Bool {
        errorMessage = nil
        do {
            let measurementDate = Self.measurementDate(day: date, timeOfDay: timeOfDay)
            try await healthKit.saveReading(
                systolic: systolic,
                diastolic: diastolic,
                pulse: pulse,
                date: measurementDate,
                syncIdentifier: "com.soma.reading.\(UUID().uuidString)",
                notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                arm: arm
            )
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteSession(_ session: BPSession) async {
        let previousSessions = sessions
        sessions.removeAll { $0.sessionId == session.sessionId }
        do {
            try await healthKit.deleteBloodPressureSample(id: session.sessionId)
        } catch {
            sessions = previousSessions
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG
    struct SeedReading: Codable {
        let id: String
        let date: String
        let timeOfDay: TimeOfDay
        let systolic: Int
        let diastolic: Int
        let pulse: Int?
    }

    struct SeedData: Codable {
        let version: Int
        let source: String
        let readings: [SeedReading]
    }

    /// Exports the canonical averaged Vercel sessions as a reusable JSON fixture.
    func exportVercelSeedData() async throws -> URL {
        let rows = try await api.fetchBloodPressureRows()
        let sourceSessions = groupRowsIntoSessions(rows)
        let seed = SeedData(
            version: 1,
            source: "Vercel averaged blood-pressure sessions",
            readings: sourceSessions.map { session in
                SeedReading(
                    id: session.sessionId,
                    date: session.date,
                    timeOfDay: session.timeOfDay,
                    systolic: session.systolic,
                    diastolic: session.diastolic,
                    pulse: session.pulse
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(seed)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BloodPressureSeed.json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Rebuilds Soma-owned HealthKit data as one averaged record per Vercel session.
    func repairHealthKitFromVercel() async throws -> (deleted: Int, imported: Int) {
        let rows = try await api.fetchBloodPressureRows()
        let sourceSessions = groupRowsIntoSessions(rows)

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"

        let exportableSessions = sourceSessions.compactMap { session -> (BPSession, Date)? in
            guard let day = formatter.date(from: session.date) else { return nil }
            return (session, Self.measurementDate(day: day, timeOfDay: session.timeOfDay))
        }

        let deleted = try await healthKit.deleteAllSomaHealthSamples()
        for (session, date) in exportableSessions {
            try await healthKit.saveReading(
                systolic: session.systolic,
                diastolic: session.diastolic,
                pulse: session.pulse,
                date: date,
                syncIdentifier: "com.soma.session.\(session.sessionId)",
                notes: nil,
                arm: nil
            )
        }

        await load()
        return (deleted, exportableSessions.count)
    }
    #endif

    private static func session(from sample: HealthSampleReading) -> BPSession {
        let reading = BPReading(
            id: sample.id,
            date: sample.dateString,
            timeOfDay: sample.timeOfDay,
            systolic: sample.systolic,
            diastolic: sample.diastolic,
            pulse: sample.pulse,
            notes: sample.notes,
            arm: sample.arm
        )
        return BPSession(
            sessionId: sample.id,
            date: sample.dateString,
            timeOfDay: sample.timeOfDay,
            systolic: sample.systolic,
            diastolic: sample.diastolic,
            pulse: sample.pulse,
            notes: sample.notes,
            readings: [reading]
        )
    }

    private static func measurementDate(day: Date, timeOfDay: TimeOfDay) -> Date {
        let hour: Int
        switch timeOfDay {
        case .morning: hour = 8
        case .afternoon: hour = 14
        case .evening: hour = 20
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .hour, value: hour, to: startOfDay) ?? day
    }
}
