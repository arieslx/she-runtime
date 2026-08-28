import Foundation
import HealthKit

protocol HRVHealthKitServicing: Sendable {
    func requestReadAuthorization() async throws
    func loadSamples(from startDate: Date, to endDate: Date) async throws -> [HRVSample]
}

final class HRVHealthKitService: HRVHealthKitServicing, @unchecked Sendable {
    enum ServiceError: LocalizedError {
        case healthDataUnavailable
        case hrvTypeUnavailable

        var errorDescription: String? {
            switch self {
            case .healthDataUnavailable: C.t("map.healthUnavailable")
            case .hrvTypeUnavailable: C.t("map.hrvTypeUnavailable")
            }
        }
    }

    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func requestReadAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw ServiceError.healthDataUnavailable }
        let type = try hrvType()
        try await healthStore.requestAuthorization(toShare: [], read: [type])
    }

    func loadSamples(from startDate: Date, to endDate: Date) async throws -> [HRVSample] {
        let type = try hrvType()
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: [.strictStartDate]
        )
        let samples: [HKQuantitySample] = try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, values, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: values as? [HKQuantitySample] ?? [])
            }
            healthStore.execute(query)
        }
        let unit = HKUnit.secondUnit(with: .milli)
        return samples.map {
            HRVSample(
                valueMs: $0.quantity.doubleValue(for: unit),
                startDate: $0.startDate,
                endDate: $0.endDate,
                sourceName: $0.sourceRevision.source.name
            )
        }
    }

    private func hrvType() throws -> HKQuantityType {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw ServiceError.hrvTypeUnavailable
        }
        return type
    }
}
