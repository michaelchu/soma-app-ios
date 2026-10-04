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
    func saveReading(systolic: Int, diastolic: Int, pulse: Int?, date: Date) async throws
    func fetchBloodPressureSamples(daysBack: Int) async throws -> [HealthSampleReading]
}

extension SomaAPIClient: SomaAPIClientProtocol {}
extension HealthKitManager: HealthKitManagerProtocol {}

// MARK: - Central BP state (mirrors the web BPContext / useReadings hook)

@MainActor
final class BPStore: ObservableObject {
    static let shared = BPStore()

    @Published private(set) var sessions: [BPSession] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let api: any SomaAPIClientProtocol
    private let healthKit: any HealthKitManagerProtocol
    private let defaults: UserDefaults

    init(
        api: any SomaAPIClientProtocol = SomaAPIClient.shared,
        healthKit: any HealthKitManagerProtocol = HealthKitManager.shared,
        defaults: UserDefaults = .standard
    ) {
        self.api = api
        self.healthKit = healthKit
        self.defaults = defaults
    }

    var isConfigured: Bool { api.isConfigured }

    // MARK: - Load

    func load() async {
        guard api.isConfigured else { return }
        isLoading = true
        errorMessage = nil
        do {
            let rows = try await api.fetchBloodPressureRows()
            sessions = groupRowsIntoSessions(rows)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Create (quick log)

    /// Logs a new session to Soma, then writes it to HealthKit (two-way sync).
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
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let dateString = df.string(from: date)
        do {
            let sessionId = try await api.createSession(
                date: dateString,
                timeOfDay: timeOfDay,
                readings: [.init(systolic: systolic, diastolic: diastolic, pulse: pulse, arm: arm)],
                notes: (notes?.isEmpty ?? true) ? nil : notes
            )
            // Write to HealthKit (best effort — Soma is the source of truth)
            try? await healthKit.saveReading(
                systolic: systolic,
                diastolic: diastolic,
                pulse: pulse,
                date: date
            )
            _ = sessionId
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Delete

    func deleteSession(_ session: BPSession) async {
        let removed = sessions
        sessions.removeAll { $0.sessionId == session.sessionId }
        do {
            try await api.deleteSession(sessionId: session.sessionId)
            rememberDeletedHealthKitKeys(Self.dedupeKeys(for: session))
        } catch {
            // Restore on failure
            sessions = removed
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - HealthKit -> Soma sync

    /// Reads BP correlations from HealthKit and imports any that aren't in Soma yet.
    /// Dedupe key: date + timeOfDay + systolic + diastolic (matches the importer's approach).
    func syncFromHealthKit() async -> (imported: Int, skipped: Int) {
        var imported = 0
        var skipped = 0
        do {
            let samples = try await healthKit.fetchBloodPressureSamples(daysBack: 365)
            var existingKeys = Set(sessions.flatMap(Self.dedupeKeys(for:)))
            existingKeys.formUnion(deletedHealthKitKeys)
            for sample in samples {
                let key = Self.dedupeKey(
                    date: sample.dateString,
                    timeOfDay: sample.timeOfDay,
                    sys: sample.systolic,
                    dia: sample.diastolic
                )
                if existingKeys.contains(key) {
                    skipped += 1
                    continue
                }
                _ = try await api.createSession(
                    date: sample.dateString,
                    timeOfDay: sample.timeOfDay,
                    readings: [.init(systolic: sample.systolic, diastolic: sample.diastolic, pulse: sample.pulse, arm: nil)],
                    notes: "Imported from Apple Health"
                )
                existingKeys.insert(key)
                imported += 1
            }
            if imported > 0 { await load() }
        } catch {
            errorMessage = error.localizedDescription
        }
        return (imported, skipped)
    }

    static func dedupeKey(date: String, timeOfDay: TimeOfDay, sys: Int, dia: Int) -> String {
        "\(date)|\(timeOfDay.rawValue)|\(sys)|\(dia)"
    }

    static func dedupeKeys(for session: BPSession) -> Set<String> {
        guard !session.readings.isEmpty else {
            return [dedupeKey(
                date: session.date,
                timeOfDay: session.timeOfDay,
                sys: session.systolic,
                dia: session.diastolic
            )]
        }
        return Set(session.readings.map {
            dedupeKey(date: $0.date, timeOfDay: $0.timeOfDay, sys: $0.systolic, dia: $0.diastolic)
        })
    }

    private static let deletedHealthKitKeysDefaultsKey = "soma.deletedHealthKitReadingKeys"

    private var deletedHealthKitKeys: Set<String> {
        Set(defaults.stringArray(forKey: Self.deletedHealthKitKeysDefaultsKey) ?? [])
    }

    private func rememberDeletedHealthKitKeys(_ keys: Set<String>) {
        defaults.set(
            Array(deletedHealthKitKeys.union(keys)),
            forKey: Self.deletedHealthKitKeysDefaultsKey
        )
    }
}
