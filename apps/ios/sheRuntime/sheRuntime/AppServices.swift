import Foundation
import Combine

@MainActor
final class AppServices: ObservableObject {
    let stopWatchBLE: StopWatchBLEService
    let dataPermissions: DataAccessPermissionService
    let stopWatchAudioPipeline: StopWatchAudioPipelineService

    init() {
        stopWatchBLE = .shared
        dataPermissions = DataAccessPermissionService()
        stopWatchAudioPipeline = StopWatchAudioPipelineService()
    }

    func activate() {
        stopWatchBLE.activateIfBound()
        dataPermissions.refreshStatuses()
    }
}
