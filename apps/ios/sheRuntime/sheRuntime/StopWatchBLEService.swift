@preconcurrency import CoreBluetooth
import Foundation

@MainActor
final class StopWatchBLEService: NSObject {
    static let deviceName = "sheRuntime-StopWatch"
    static let serviceUUID = CBUUID(string: "a7f00001-4d7a-4e6b-9f30-6a8e2a14c001")
    static let commandUUID = CBUUID(string: "a7f00002-4d7a-4e6b-9f30-6a8e2a14c001")
    static let responseUUID = CBUUID(string: "a7f00003-4d7a-4e6b-9f30-6a8e2a14c001")

    var onBluetoothStateChanged: ((String) -> Void)?
    var onStatusChanged: ((String) -> Void)?
    var onDeviceDiscovered: ((String, Int) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?
    var onWritableChanged: ((Bool) -> Void)?
    var onSubscriptionChanged: ((Bool) -> Void)?
    var onResponse: ((String, TimeInterval?) -> Void)?
    var onFailure: ((String) -> Void)?

    private var centralManager: CBCentralManager!
    private var discoveredPeripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var responseCharacteristic: CBCharacteristic?
    private var pingSentAt: Date?

    override init() {
        super.init()
    }

    func activate() {
        guard centralManager == nil else { return }
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func startScanning() {
        guard centralManager.state == .poweredOn else {
            fail("蓝牙尚未打开，无法扫描")
            return
        }
        resetConnectionResources(keepPeripheral: false)
        onStatusChanged?("正在扫描指定 Service UUID…")
        centralManager.scanForPeripherals(
            withServices: [Self.serviceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScanning() {
        centralManager.stopScan()
    }

    func connect() {
        guard let discoveredPeripheral else {
            fail("尚未发现 StopWatch，请先扫描")
            return
        }
        centralManager.stopScan()
        onStatusChanged?("正在连接 \(discoveredPeripheral.name ?? Self.deviceName)…")
        centralManager.connect(discoveredPeripheral)
    }

    func disconnect() {
        centralManager.stopScan()
        guard let discoveredPeripheral else {
            onStatusChanged?("当前没有已连接设备")
            return
        }
        onStatusChanged?("正在主动断开…")
        centralManager.cancelPeripheralConnection(discoveredPeripheral)
    }

    func sendPing() {
        guard let peripheral = discoveredPeripheral,
              let commandCharacteristic,
              let responseCharacteristic,
              responseCharacteristic.isNotifying else {
            fail("Command 尚不可写或 Response Notify 尚未订阅")
            return
        }
        guard let data = "ping".data(using: .utf8) else {
            fail("无法编码 ping")
            return
        }

        let writeType: CBCharacteristicWriteType = commandCharacteristic.properties.contains(.write)
            ? .withResponse
            : .withoutResponse
        pingSentAt = Date()
        peripheral.writeValue(data, for: commandCharacteristic, type: writeType)
        onStatusChanged?("已发送 ping，等待 pong…")
    }

    private func resetConnectionResources(keepPeripheral: Bool) {
        commandCharacteristic = nil
        responseCharacteristic = nil
        pingSentAt = nil
        if !keepPeripheral { discoveredPeripheral = nil }
        onWritableChanged?(false)
        onSubscriptionChanged?(false)
    }

    private func fail(_ message: String) {
        onStatusChanged?("失败")
        onFailure?(message)
    }
}

extension StopWatchBLEService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let description: String
        switch central.state {
        case .unknown: description = "未知"
        case .resetting: description = "正在重置"
        case .unsupported: description = "设备不支持 BLE"
        case .unauthorized: description = "蓝牙权限未授权"
        case .poweredOff: description = "蓝牙已关闭"
        case .poweredOn: description = "蓝牙已打开"
        @unknown default: description = "未知状态"
        }
        onBluetoothStateChanged?(description)
        onStatusChanged?(central.state == .poweredOn ? "可以开始扫描" : description)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard discoveredPeripheral == nil else { return }
        discoveredPeripheral = peripheral
        central.stopScan()
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? "未命名设备"
        onDeviceDiscovered?(name, RSSI.intValue)
        onStatusChanged?("已发现设备")
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        onConnectionChanged?(true)
        onStatusChanged?("已连接，正在发现 Service…")
        peripheral.discoverServices([Self.serviceUUID])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        onConnectionChanged?(false)
        resetConnectionResources(keepPeripheral: true)
        fail("连接失败：\(error?.localizedDescription ?? "未知错误")")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        timestamp: CFAbsoluteTime,
        isReconnecting: Bool,
        error: Error?
    ) {
        onConnectionChanged?(false)
        resetConnectionResources(keepPeripheral: false)
        if let error {
            fail("连接已断开：\(error.localizedDescription)")
        } else {
            onStatusChanged?("已断开；可手动重新扫描")
        }
    }
}

extension StopWatchBLEService: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { fail("发现 Service 失败：\(error.localizedDescription)"); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceUUID }) else {
            fail("未发现指定 Service")
            return
        }
        onStatusChanged?("已发现 Service，正在发现 Characteristic…")
        peripheral.discoverCharacteristics(
            [Self.commandUUID, Self.responseUUID],
            for: service
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error { fail("发现 Characteristic 失败：\(error.localizedDescription)"); return }
        for characteristic in service.characteristics ?? [] {
            if characteristic.uuid == Self.commandUUID {
                commandCharacteristic = characteristic
            } else if characteristic.uuid == Self.responseUUID {
                responseCharacteristic = characteristic
            }
        }

        guard let commandCharacteristic,
              commandCharacteristic.properties.contains(.write) ||
                commandCharacteristic.properties.contains(.writeWithoutResponse) else {
            fail("Command Characteristic 不可写")
            return
        }
        onWritableChanged?(true)
        onStatusChanged?("Command 可写，正在订阅 Response Notify…")

        guard let responseCharacteristic,
              responseCharacteristic.properties.contains(.notify) else {
            fail("Response Characteristic 不支持 Notify")
            return
        }
        peripheral.setNotifyValue(true, for: responseCharacteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error { fail("订阅 Notify 失败：\(error.localizedDescription)"); return }
        guard characteristic.uuid == Self.responseUUID else { return }
        onSubscriptionChanged?(characteristic.isNotifying)
        onStatusChanged?(characteristic.isNotifying ? "Response Notify 已订阅" : "Response Notify 未订阅")
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error { fail("写入 ping 失败：\(error.localizedDescription)") }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error { fail("接收 Notify 失败：\(error.localizedDescription)"); return }
        guard characteristic.uuid == Self.responseUUID,
              let value = characteristic.value,
              let text = String(data: value, encoding: .utf8) else {
            fail("收到无法解析的 Response 数据")
            return
        }
        let roundTrip = pingSentAt.map { Date().timeIntervalSince($0) }
        pingSentAt = nil
        onResponse?(text, roundTrip)
        onStatusChanged?("已收到 Response Notify")
    }
}
