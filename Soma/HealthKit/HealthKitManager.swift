import Foundation
import HealthKit

// MARK: - HealthKit two-way sync
//
// Lessons from the SomaImporter (Oct 2026):
// - NEVER request share authorization for the HKCorrelationType blood-pressure
//   type itself — HealthKit throws NSInvalidArgumentException. Authorize only
//   the systolic/diastolic/heart-rate quantity types; correlations still save.

struct HealthSampleReading {
    let id: String
    let date: Date
    let dateString: String // YYYY-MM-DD
    let timeOfDay: TimeOfDay
    let systolic: Int
    let diastolic: Int
    let pulse: Int?
    let notes: String?
    let arm: Arm?
}

final class HealthKitManager {
    static let shared = HealthKitManager()

    private let store = HKHealthStore()
    private static let notesMetadataKey = "com.soma.notes"
    private static let armMetadataKey = "com.soma.arm"

    private var systolicType: HKQuantityType {
        HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic)!
    }
    private var diastolicType: HKQuantityType {
        HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic)!
    }
    private var heartRateType: HKQuantityType {
        HKQuantityType.quantityType(forIdentifier: .heartRate)!
    }
    private var bpCorrelationType: HKCorrelationType {
        HKCorrelationType.correlationType(forIdentifier: .bloodPressure)!
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    enum AuthStatus {
        case notDetermined, authorized, denied
    }

    func authorizationStatus() -> AuthStatus {
        let s = store.authorizationStatus(for: systolicType)
        switch s {
        case .notDetermined: return .notDetermined
        case .sharingAuthorized: return .authorized
        case .sharingDenied: return .denied
        @unknown default: return .notDetermined
        }
    }

    /// Requests share access for the quantity types and read access for
    /// quantities + the BP correlation type. Never requests share on the
    /// correlation type (see note above).
    func requestAuthorization() async throws {
        let share: Set<HKSampleType> = [systolicType, diastolicType, heartRateType]
        // Never include the BP correlation type in read/share authorization —
        // iOS disallows it (NSInvalidArgumentException). Authorize only the
        // quantity types; correlations read/write fine on top of those.
        let read: Set<HKObjectType> = [systolicType, diastolicType, heartRateType]
        try await store.requestAuthorization(toShare: share, read: read)
    }

    // MARK: - Write: Soma -> HealthKit

    func saveReading(
        systolic: Int,
        diastolic: Int,
        pulse: Int?,
        date: Date,
        syncIdentifier: String?,
        notes: String?,
        arm: Arm?
    ) async throws {
        let mmHg = HKUnit.millimeterOfMercury()
        let systolicSample = HKQuantitySample(
            type: systolicType,
            quantity: HKQuantity(unit: mmHg, doubleValue: Double(systolic)),
            start: date,
            end: date
        )
        let diastolicSample = HKQuantitySample(
            type: diastolicType,
            quantity: HKQuantity(unit: mmHg, doubleValue: Double(diastolic)),
            start: date,
            end: date
        )
        var metadata: [String: Any] = [:]
        if let syncIdentifier {
            metadata[HKMetadataKeySyncIdentifier] = syncIdentifier
            metadata[HKMetadataKeySyncVersion] = 1
        }
        if let notes, !notes.isEmpty {
            metadata[Self.notesMetadataKey] = notes
        }
        if let arm {
            metadata[Self.armMetadataKey] = arm.rawValue
        }
        let correlation = HKCorrelation(
            type: bpCorrelationType,
            start: date,
            end: date,
            objects: [systolicSample, diastolicSample],
            device: nil,
            metadata: metadata.isEmpty ? nil : metadata
        )

        var samples: [HKSample] = [correlation]
        if let pulse {
            let heartRateMetadata = syncIdentifier.map {
                [
                    HKMetadataKeySyncIdentifier: "\($0).heart-rate",
                    HKMetadataKeySyncVersion: 1
                ] as [String: Any]
            }
            let heartRateSample = HKQuantitySample(
                type: heartRateType,
                quantity: HKQuantity(
                    unit: HKUnit.count().unitDivided(by: .minute()),
                    doubleValue: Double(pulse)
                ),
                start: date,
                end: date,
                metadata: heartRateMetadata
            )
            samples.append(heartRateSample)
        }

        try await store.save(samples)
    }

    /// Deletes every blood-pressure correlation and heart-rate sample saved by Soma.
    /// HealthKit prevents an app from deleting samples written by other sources.
    func deleteAllSomaHealthSamples() async throws -> Int {
        let bloodPressureSamples = try await samplesSavedBySoma(of: bpCorrelationType)
        let heartRateSamples = try await samplesSavedBySoma(of: heartRateType)
        let samples = bloodPressureSamples + heartRateSamples

        guard !samples.isEmpty else { return 0 }
        try await store.delete(samples)
        return samples.count
    }

    private func samplesSavedBySoma(of type: HKSampleType) async throws -> [HKSample] {
        let predicate = HKQuery.predicateForObjects(from: .default())
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            self.store.execute(query)
        }
    }

    func deleteBloodPressureSample(id: String) async throws {
        guard let uuid = UUID(uuidString: id) else { return }
        let predicate = HKQuery.predicateForObject(with: uuid)
        let samples: [HKSample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bpCorrelationType,
                predicate: predicate,
                limit: 1,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            self.store.execute(query)
        }
        guard let correlation = samples.first as? HKCorrelation else { return }
        var linkedSamples: [HKSample] = [correlation]
        if let syncIdentifier = correlation.metadata?[HKMetadataKeySyncIdentifier] as? String {
            let heartRateIdentifier = "\(syncIdentifier).heart-rate"
            let heartRateSamples = try await samplesSavedBySoma(of: heartRateType).filter {
                ($0.metadata?[HKMetadataKeySyncIdentifier] as? String) == heartRateIdentifier
            }
            linkedSamples.append(contentsOf: heartRateSamples)
        }
        try await store.delete(linkedSamples)
    }

    // MARK: - Read: HealthKit -> Soma

    func fetchBloodPressureSamples(daysBack: Int = 365) async throws -> [HealthSampleReading] {
        let now = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: now) else {
            return []
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
        let correlations = try await fetchSamples(of: bpCorrelationType, predicate: predicate)
            .compactMap { $0 as? HKCorrelation }
        let heartRates = try await fetchSamples(of: heartRateType, predicate: predicate)
            .compactMap { $0 as? HKQuantitySample }

        var pulseByIdentifier: [String: Int] = [:]
        for sample in heartRates {
            guard let identifier = sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
                  identifier.hasSuffix(".heart-rate") else {
                continue
            }
            let parentIdentifier = String(identifier.dropLast(".heart-rate".count))
            let pulse = Int(
                sample.quantity.doubleValue(
                    for: HKUnit.count().unitDivided(by: .minute())
                ).rounded()
            )
            pulseByIdentifier[parentIdentifier] = pulse
        }

        return correlations.compactMap { correlation in
            let identifier = correlation.metadata?[HKMetadataKeySyncIdentifier] as? String
            return Self.reading(
                from: correlation,
                pulse: identifier.flatMap { pulseByIdentifier[$0] }
            )
        }
    }

    private func fetchSamples(
        of type: HKSampleType,
        predicate: NSPredicate
    ) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [
                    NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
                ]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            store.execute(query)
        }
    }

    private static func reading(
        from correlation: HKCorrelation,
        pulse: Int?
    ) -> HealthSampleReading? {
        var sys: Int?
        var dia: Int?
        for sample in correlation.objects {
            guard let q = sample as? HKQuantitySample else { continue }
            switch q.quantityType {
            case HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic):
                sys = Int(q.quantity.doubleValue(for: HKUnit.millimeterOfMercury()).rounded())
            case HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic):
                dia = Int(q.quantity.doubleValue(for: HKUnit.millimeterOfMercury()).rounded())
            default:
                break
            }
        }
        guard let sys, let dia else { return nil }
        let date = correlation.startDate
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let hour = Calendar.current.component(.hour, from: date)
        let tod: TimeOfDay = (6..<12).contains(hour) ? .morning : (12..<18).contains(hour) ? .afternoon : .evening
        return HealthSampleReading(
            id: correlation.uuid.uuidString,
            date: date,
            dateString: df.string(from: date),
            timeOfDay: tod,
            systolic: sys,
            diastolic: dia,
            pulse: pulse,
            notes: correlation.metadata?[Self.notesMetadataKey] as? String,
            arm: (correlation.metadata?[Self.armMetadataKey] as? String).flatMap(Arm.init(rawValue:))
        )
    }
}
