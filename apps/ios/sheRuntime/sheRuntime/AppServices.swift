import Foundation
import Combine

@MainActor
final class AppServices: ObservableObject {
    let stopWatchBLE: StopWatchBLEService
    let dataPermissions: DataAccessPermissionService
    let stopWatchAudioPipeline: StopWatchAudioPipelineService
    let energyMap: EnergyMapViewModel

    init() {
        stopWatchBLE = .shared
        dataPermissions = DataAccessPermissionService()
        stopWatchAudioPipeline = StopWatchAudioPipelineService()
        energyMap = EnergyMapViewModel()
    }

    func activate() {
        stopWatchBLE.activateIfBound()
        dataPermissions.refreshStatuses()
    }
}
