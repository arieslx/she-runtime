import Foundation

enum DataAccessPermissionStatus: Equatable {
    case notRequested
    case allowed
    case denied
    case restricted
    case unavailable

    var copyKey: String {
        switch self {
        case .notRequested: "dataPrivacy.permission.notRequested"
        case .allowed: "dataPrivacy.permission.allowed"
        case .denied: "dataPrivacy.permission.denied"
        case .restricted: "dataPrivacy.permission.restricted"
        case .unavailable: "dataPrivacy.permission.unavailable"
        }
    }
}

enum StopWatchBluetoothSystemStatus: Equatable {
    case notAuthorized
    case authorized
    case poweredOff
    case unsupported

    var copyKey: String {
        switch self {
        case .notAuthorized: "dataPrivacy.bluetooth.notAuthorized"
        case .authorized: "dataPrivacy.bluetooth.authorized"
        case .poweredOff: "dataPrivacy.bluetooth.poweredOff"
        case .unsupported: "dataPrivacy.bluetooth.unsupported"
        }
    }
}

enum StopWatchConnectionStatus: Equatable {
    case unbound
    case scanning
    case connecting
    case connected
    case receiving
    case disconnected
    case failed

    var copyKey: String {
        switch self {
        case .unbound: "dataPrivacy.stopWatch.unbound"
        case .scanning: "dataPrivacy.stopWatch.scanning"
        case .connecting: "dataPrivacy.stopWatch.connecting"
        case .connected: "dataPrivacy.stopWatch.connected"
        case .receiving: "dataPrivacy.stopWatch.receiving"
        case .disconnected: "dataPrivacy.stopWatch.disconnected"
        case .failed: "dataPrivacy.stopWatch.failed"
        }
    }
}
