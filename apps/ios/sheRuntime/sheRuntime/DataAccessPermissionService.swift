import AVFoundation
import Combine
@preconcurrency import CoreBluetooth
import Foundation
import HealthKit
import UIKit

@MainActor
final class DataAccessPermissionService: ObservableObject {
    @Published private(set) var healthStatus: DataAccessPermissionStatus = .notRequested
    @Published private(set) var microphoneStatus: DataAccessPermissionStatus = .notRequested

    private let healthKitManager: HealthKitManager
    private let userDefaults: UserDefaults
    private let healthRequestedKey = "dataPrivacy.healthKitRequested"

    init(healthKitManager: HealthKitManager? = nil, userDefaults: UserDefaults = .standard) {
        self.healthKitManager = healthKitManager ?? HealthKitManager()
        self.userDefaults = userDefaults
        refreshStatuses()
    }

    func refreshStatuses() {
        refreshHealthStatus()
        refreshMicrophoneStatus()
    }

    func requestHealthAccess() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthStatus = .unavailable
            return
        }

        do {
            try await healthKitManager.requestReadAuthorization()
            userDefaults.set(true, forKey: healthRequestedKey)
            // marktag: HealthKit intentionally does not expose reliable read-authorization state
            // for every requested read type. A successful request means the system sheet completed;
            // nil query results must not be treated as denial.
            healthStatus = .allowed
        } catch let error as HealthKitManager.ManagerError {
            switch error {
            case .unavailable:
                healthStatus = .unavailable
            case .missingDataType:
                healthStatus = .restricted
            }
        } catch {
            healthStatus = .restricted
        }
    }

    func requestMicrophoneAccess() async {
#if os(iOS)
        if #available(iOS 17.0, *) {
            let granted = await AVAudioApplication.requestRecordPermission()
            microphoneStatus = granted ? .allowed : .denied
        } else {
            await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    Task { @MainActor in
                        self.microphoneStatus = granted ? .allowed : .denied
                        continuation.resume()
                    }
                }
            }
        }
#else
        microphoneStatus = .unavailable
#endif
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func refreshHealthStatus() {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthStatus = .unavailable
            return
        }
        // marktag: There is no stable public read-permission query for HealthKit read types.
        // Persisting "requested" only avoids showing the initial CTA forever; do not infer
        // HealthKit denial from missing samples.
        healthStatus = userDefaults.bool(forKey: healthRequestedKey) ? .allowed : .notRequested
    }

    private func refreshMicrophoneStatus() {
#if os(iOS)
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .undetermined:
                microphoneStatus = .notRequested
            case .denied:
                microphoneStatus = .denied
            case .granted:
                microphoneStatus = .allowed
            @unknown default:
                microphoneStatus = .restricted
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .undetermined:
                microphoneStatus = .notRequested
            case .denied:
                microphoneStatus = .denied
            case .granted:
                microphoneStatus = .allowed
            @unknown default:
                microphoneStatus = .restricted
            }
        }
#else
        microphoneStatus = .unavailable
#endif
    }
}
