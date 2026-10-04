import Foundation
import HealthKit

// MARK: - HealthKit two-way sync
//
// Lessons from the SomaImporter (Oct 2026):
// - NEVER request share authorization for the HKCorrelationType blood-pressure
//   type itself — HealthKit throws NSInvalidArgumentException. Authorize only
//   the systolic/diastolic/heart-rate quantity types; correlations still save.

struct HealthSampleReading {
    let date: Date
    let dateString: String // YYYY-MM-DD
    let timeOfDay: TimeOfDay
    let systolic: Int
    let diastolic: Int
    let pulse: Int?
}

final class HealthKitManager {
    static let shared = HealthKitManager()

    private let store = HKHealthStore()

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

    func saveReading(systolic: Int, diastolic: Int, pulse: Int?, date: Date) async throws {
        let mmHg = HKUnit.millimeterOfMercury()
        let sysSample = HKQuantitySample(
            type: systolicType,
            quantity: HKQuantity(unit: mmHg, doubleValue: Double(systolic)),
            start: date, end: date
        )
        let diaSample = HKQuantitySample(
            type: diastolicType,
            quantity: HKQuantity(unit: mmHg, doubleValue: Double(diastolic)),
            start: date, end: date
        )
        var objects: Set<HKSample> = [sysSample, diaSample]
        if let pulse {
            let hrSample = HKQuantitySample(
                type: heartRateType,
                quantity: HKQuantity(unit: HKUnit.count().unitDivided(by: .minute()), doubleValue: Double(pulse)),
                start: date, end: date
            )
            objects.insert(hrSample)
        }
        let correlation = HKCorrelation(type: bpCorrelationType, start: date, end: date, objects: objects)
        try await store.save(correlation)
    }

    // MARK: - Read: HealthKit -> Soma

    func fetchBloodPressureSamples(daysBack: Int = 365) async throws -> [HealthSampleReading] {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bpCorrelationType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let readings: [HealthSampleReading] = (samples as? [HKCorrelation] ?? []).compactMap { corr in
                    Self.reading(from: corr)
                }
                continuation.resume(returning: readings)
            }
            self.store.execute(query)
        }
    }

    private static func reading(from correlation: HKCorrelation) -> HealthSampleReading? {
        var sys: Int?
        var dia: Int?
        var pulse: Int?
        for sample in correlation.objects {
            guard let q = sample as? HKQuantitySample else { continue }
            switch q.quantityType {
            case HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic):
                sys = Int(q.quantity.doubleValue(for: HKUnit.millimeterOfMercury()).rounded())
            case HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic):
                dia = Int(q.quantity.doubleValue(for: HKUnit.millimeterOfMercury()).rounded())
            case HKQuantityType.quantityType(forIdentifier: .heartRate):
                pulse = Int(q.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
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
            date: date,
            dateString: df.string(from: date),
            timeOfDay: tod,
            systolic: sys,
            diastolic: dia,
            pulse: pulse
        )
    }
}
