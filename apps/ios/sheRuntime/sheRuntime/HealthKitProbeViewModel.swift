import Combine
import Foundation

@MainActor
final class HealthKitProbeViewModel: ObservableObject {
    enum LoadingState: Equatable {
        case idle, loading, loaded, empty
        case error(String)
    }

    @Published private(set) var state: LoadingState = .idle
    @Published private(set) var stepCount: Int?
    @Published private(set) var latestHRV: HRVReading?
    @Published private(set) var latestRestingHeartRate: RestingHeartRateReading?
    @Published private(set) var sleepSummary: SleepSummary?

    private let healthKitManager: HealthKitManager

    init() {
        healthKitManager = HealthKitManager()
    }

    init(healthKitManager: HealthKitManager) {
        self.healthKitManager = healthKitManager
    }

    var hasLoaded: Bool {
        switch state {
        case .loaded, .empty, .error: true
        case .idle, .loading: false
        }
    }

    func authorizeAndLoad() async {
        state = .loading
        do {
            try await healthKitManager.requestReadAuthorization()
            async let steps = healthKitManager.loadTodaySteps()
            async let hrv = healthKitManager.loadLatestHRV()
            async let restingHeartRate = healthKitManager.loadLatestRestingHeartRate()
            async let sleep = healthKitManager.loadLatestPrimarySleep()

            let values = try await (steps, hrv, restingHeartRate, sleep)
            stepCount = values.0
            latestHRV = values.1
            latestRestingHeartRate = values.2
            sleepSummary = values.3
            state = values.0 == nil && values.1 == nil && values.2 == nil && values.3 == nil
                ? .empty
                : .loaded
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}
