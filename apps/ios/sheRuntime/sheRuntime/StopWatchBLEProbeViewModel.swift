import Combine
import Foundation

@MainActor
final class StopWatchBLEProbeViewModel: ObservableObject {
    @Published private(set) var bluetoothState = "正在初始化…"
    @Published private(set) var status = "等待蓝牙状态"
    @Published private(set) var discoveredName: String?
    @Published private(set) var rssi: Int?
    @Published private(set) var isConnected = false
    @Published private(set) var isWritable = false
    @Published private(set) var isSubscribed = false
    @Published private(set) var responseText: String?
    @Published private(set) var roundTripMilliseconds: Double?
    @Published private(set) var errorMessage: String?
    @Published private(set) var stream = StopWatchBLEService.StreamSnapshot()

    private let service: StopWatchBLEService

    init() {
        let service = StopWatchBLEService()
        self.service = service

        service.onBluetoothStateChanged = { [weak self] in self?.bluetoothState = $0 }
        service.onStatusChanged = { [weak self] in self?.status = $0 }
        service.onDeviceDiscovered = { [weak self] name, rssi in
            self?.discoveredName = name
            self?.rssi = rssi
            self?.errorMessage = nil
        }
        service.onConnectionChanged = { [weak self] in self?.isConnected = $0 }
        service.onWritableChanged = { [weak self] in self?.isWritable = $0 }
        service.onSubscriptionChanged = { [weak self] in self?.isSubscribed = $0 }
        service.onResponse = { [weak self] text, seconds in
            self?.responseText = text
            self?.roundTripMilliseconds = seconds.map { $0 * 1_000 }
            self?.errorMessage = nil
        }
        service.onFailure = { [weak self] in self?.errorMessage = $0 }
        service.onStreamUpdate = { [weak self] snapshot in
            self?.stream = snapshot
            if snapshot.result?.hasPrefix("失败") == true {
                self?.errorMessage = snapshot.result
            }
        }
        service.activate()
    }

    var canConnect: Bool { discoveredName != nil && !isConnected }
    var canSendPing: Bool { isConnected && isWritable && isSubscribed && !stream.isActive }
    var canStartStream: Bool { isConnected && isWritable && isSubscribed && !stream.isActive }

    func scan() {
        discoveredName = nil
        rssi = nil
        responseText = nil
        roundTripMilliseconds = nil
        errorMessage = nil
        service.startScanning()
    }

    func connect() { service.connect() }
    func disconnect() { service.disconnect() }

    func sendPing() {
        responseText = nil
        roundTripMilliseconds = nil
        errorMessage = nil
        service.sendPing()
    }

    func startStreamTest() {
        errorMessage = nil
        service.startStreamTest()
    }

    func stopScanning() { service.stopScanning() }
}
