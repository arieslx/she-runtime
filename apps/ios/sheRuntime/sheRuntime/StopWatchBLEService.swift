@preconcurrency import CoreBluetooth
import Foundation

@MainActor
final class StopWatchBLEService: NSObject {
    struct StreamSnapshot: Equatable {
        var isActive = false
        var notifyLength: Int?
        var sessionId: UInt16?
        var expectedFrames = 0
        var receivedFrames = 0
        var expectedPayloadBytes = 0
        var receivedPayloadBytes = 0
        var currentSequence: Int?
        var missingFrames = 0
        var duplicateFrames = 0
        var expectedCRC32: UInt32?
        var actualCRC32: UInt32?
        var elapsedSeconds: TimeInterval?
        var speedKBPerSecond: Double?
        var confirmationSent = false
        var result: String?
    }

    private final class StreamContext {
        let sessionId: UInt16
        let totalFrames: Int
        let frameSize: Int
        let payloadBytes: Int
        let startedAt: Date
        var frames: [Data?]
        var receivedFrames = 0
        var receivedBytes = 0
        var currentSequence: Int?
        var duplicateFrames = 0
        var protocolErrors: [String] = []
        var lastProgressPublishedAt = Date.distantPast

        init(sessionId: UInt16, totalFrames: Int, frameSize: Int, payloadBytes: Int) {
            self.sessionId = sessionId
            self.totalFrames = totalFrames
            self.frameSize = frameSize
            self.payloadBytes = payloadBytes
            startedAt = Date()
            frames = Array(repeating: nil, count: totalFrames)
        }
    }

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
    var onStreamUpdate: ((StreamSnapshot) -> Void)?

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var responseCharacteristic: CBCharacteristic?
    private var pingSentAt: Date?
    private var stream: StreamContext?
    private var streamRequested = false

    func activate() {
        guard centralManager == nil else { return }
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    func startScanning() {
        guard centralManager.state == .poweredOn else { fail("蓝牙尚未打开，无法扫描"); return }
        guard !streamRequested else { fail("流传输期间不能重新扫描"); return }
        resetConnection(keepPeripheral: false)
        onStatusChanged?("正在扫描指定 Service UUID…")
        centralManager.scanForPeripherals(withServices: [Self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    func stopScanning() { centralManager.stopScan() }
    func connect() {
        guard let peripheral else { fail("尚未发现 StopWatch，请先扫描"); return }
        centralManager.stopScan(); onStatusChanged?("正在连接 \(peripheral.name ?? Self.deviceName)…")
        centralManager.connect(peripheral)
    }
    func disconnect() {
        centralManager.stopScan()
        guard let peripheral else { onStatusChanged?("当前没有已连接设备"); return }
        centralManager.cancelPeripheralConnection(peripheral)
    }
    func sendPing() {
        guard !streamRequested else { fail("音频流期间不能发送 ping"); return }
        pingSentAt = Date()
        guard writeCommand("ping") else { pingSentAt = nil; return }
        onStatusChanged?("已发送 ping，等待 pong…")
    }
    func startStreamTest() {
        guard !streamRequested else { fail("已有音频流测试正在进行"); return }
        guard canWrite else { fail("Command 尚不可写或 Response Notify 尚未订阅"); return }
        streamRequested = true; stream = nil
        onStreamUpdate?(StreamSnapshot(isActive: true, result: "等待 META"))
        guard writeCommand("START_STREAM_TEST") else {
            failStream("START_STREAM_TEST 写入失败", sendFailure: false); return
        }
        onStatusChanged?("已发送 START_STREAM_TEST，等待 META…")
    }

    private var canWrite: Bool {
        peripheral != nil && commandCharacteristic != nil && responseCharacteristic?.isNotifying == true
    }
    @discardableResult private func writeCommand(_ text: String) -> Bool {
        guard let peripheral, let commandCharacteristic, let data = text.data(using: .utf8) else {
            fail("无法写入 Command"); return false
        }
        let type: CBCharacteristicWriteType = commandCharacteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: commandCharacteristic, type: type); return true
    }
    private func resetConnection(keepPeripheral: Bool) {
        commandCharacteristic = nil; responseCharacteristic = nil; pingSentAt = nil
        if !keepPeripheral { peripheral = nil }
        onWritableChanged?(false); onSubscriptionChanged?(false)
    }
    private func handleNotify(_ data: Data) {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { fail("收到空 Notify"); return }
        if bytes.count == 174 { handleAudio(bytes); return }
        if let context = stream, !(bytes.count == 13 && bytes[0] == 0x22) {
            failStream("AUDIO Notify 长度不是 174（实际 \(bytes.count)）", sessionId: context.sessionId)
            return
        }
        switch bytes[0] {
        case 0x20: handleMeta(bytes)
        case 0x22: handleEnd(bytes)
        default:
            guard let text = String(data: data, encoding: .utf8) else { fail("收到未知 Notify 数据"); return }
            let elapsed = pingSentAt.map { Date().timeIntervalSince($0) }; pingSentAt = nil
            onResponse?(text, elapsed); onStatusChanged?("已收到 Response Notify")
        }
    }
    private func handleMeta(_ bytes: [UInt8]) {
        guard streamRequested else { return }
        guard stream == nil else { failStream("重复收到 META"); return }
        guard bytes.count == 14,
              let id = u16(bytes, 1), let frames = u16(bytes, 3),
              let size = u16(bytes, 5), let payload = u32(bytes, 7) else {
            failStream("META 格式错误", sendFailure: false); return
        }
        guard frames == 500, size == 174, payload == 80_000 else {
            failStream("META 参数不符合流协议", sessionId: id); return
        }
        let context = StreamContext(sessionId: id, totalFrames: 500, frameSize: 174, payloadBytes: 80_000)
        stream = context; publish(context, active: true, result: "接收中", notifyLength: nil)
        onStatusChanged?("已收到 META，开始接收模拟 ADPCM 帧…")
    }
    private func handleAudio(_ bytes: [UInt8]) {
        guard streamRequested else { return }
        guard let context = stream else { failStream("在 META 前收到 AUDIO", sendFailure: false); return }
        guard bytes.count == context.frameSize else { failStream("AUDIO Notify 长度不是 174", sessionId: context.sessionId); return }
        guard let seqValue = u16(bytes, 0), let sampleIndex = u32(bytes, 4), let sampleCount = u16(bytes, 8) else {
            failStream("AUDIO 头解析失败", sessionId: context.sessionId); return
        }
        let seq = Int(seqValue); context.currentSequence = seq
        guard bytes[2] == 0x01, bytes[3] == 0, sampleCount == 320,
              sampleIndex == UInt32(seq) * 320, bytes[10] == 0, bytes[11] == 0,
              bytes[12] == 0, bytes[13] == 0 else {
            context.protocolErrors.append("AUDIO codec 或采样字段错误"); maybePublish(context, notifyLength: bytes.count); return
        }
        guard seq < context.totalFrames else {
            context.protocolErrors.append("sequence 越界"); maybePublish(context, notifyLength: bytes.count); return
        }
        if context.frames[seq] != nil {
            context.duplicateFrames += 1
        } else {
            let payload = Data(bytes[14..<174]); context.frames[seq] = payload
            context.receivedFrames += 1; context.receivedBytes += payload.count
        }
        maybePublish(context, notifyLength: bytes.count)
    }
    private func maybePublish(_ context: StreamContext, notifyLength: Int) {
        let now = Date()
        guard now.timeIntervalSince(context.lastProgressPublishedAt) >= 0.1 || context.receivedFrames == context.totalFrames else { return }
        context.lastProgressPublishedAt = now
        publish(context, active: true, result: "接收中", notifyLength: notifyLength)
    }
    private func handleEnd(_ bytes: [UInt8]) {
        guard streamRequested, let context = stream else { return }
        guard bytes.count == 13, let id = u16(bytes, 1), let frames = u16(bytes, 3),
              let payloadBytes = u32(bytes, 5), let crc = u32(bytes, 9), id == context.sessionId else {
            failStream("END 格式或 sessionId 错误"); return
        }
        finalize(context, endFrames: Int(frames), endPayloadBytes: Int(payloadBytes), expectedCRC: crc)
    }
    private func finalize(_ context: StreamContext, endFrames: Int, endPayloadBytes: Int, expectedCRC: UInt32) {
        let missing = context.frames.filter { $0 == nil }.count
        var payload = Data(capacity: context.payloadBytes)
        for frame in context.frames { if let frame { payload.append(frame) } }
        let actualCRC = Self.crc32(payload)
        let contentOK = payload.enumerated().allSatisfy { $0.element == UInt8($0.offset % 256) }
        let success = endFrames == context.totalFrames && endPayloadBytes == context.payloadBytes &&
            context.receivedFrames == context.totalFrames && missing == 0 &&
            payload.count == context.payloadBytes && actualCRC == expectedCRC && contentOK &&
            context.protocolErrors.isEmpty
        let result: String
        if success { result = "成功" }
        else if let error = context.protocolErrors.first { result = "失败：\(error)" }
        else if missing > 0 { result = "失败：缺失 \(missing) 帧" }
        else if payload.count != context.payloadBytes { result = "失败：payload 长度不一致" }
        else if actualCRC != expectedCRC { result = "失败：CRC32 不一致" }
        else { result = "失败：payload 内容不一致" }
        let elapsed = Date().timeIntervalSince(context.startedAt)
        var snapshot = makeSnapshot(context, active: false, result: result, notifyLength: 174)
        snapshot.expectedCRC32 = expectedCRC; snapshot.actualCRC32 = actualCRC
        snapshot.elapsedSeconds = elapsed
        snapshot.speedKBPerSecond = elapsed > 0 ? Double(payload.count) / 1024 / elapsed : nil
        snapshot.confirmationSent = writeCommand("\(success ? "RECEIVED" : "FAILED"):\(context.sessionId)")
        onStreamUpdate?(snapshot)
        onStatusChanged?(success ? "流校验成功，已发送 RECEIVED" : "流校验失败，已发送 FAILED")
        streamRequested = false; stream = nil
    }
    private func failStream(_ reason: String, sessionId: UInt16? = nil, sendFailure: Bool = true) {
        let id = sessionId ?? stream?.sessionId
        var snapshot = stream.map { makeSnapshot($0, active: false, result: "失败：\(reason)", notifyLength: nil) }
            ?? StreamSnapshot(isActive: false, sessionId: id, result: "失败：\(reason)")
        if let context = stream {
            let elapsed = Date().timeIntervalSince(context.startedAt); snapshot.elapsedSeconds = elapsed
            snapshot.speedKBPerSecond = elapsed > 0 ? Double(context.receivedBytes) / 1024 / elapsed : nil
        }
        if sendFailure, let id { snapshot.confirmationSent = writeCommand("FAILED:\(id)") }
        onStreamUpdate?(snapshot); streamRequested = false; stream = nil
        onStatusChanged?("模拟音频流失败")
    }
    private func publish(_ context: StreamContext, active: Bool, result: String, notifyLength: Int?) {
        onStreamUpdate?(makeSnapshot(context, active: active, result: result, notifyLength: notifyLength))
    }
    private func makeSnapshot(_ c: StreamContext, active: Bool, result: String, notifyLength: Int?) -> StreamSnapshot {
        StreamSnapshot(isActive: active, notifyLength: notifyLength, sessionId: c.sessionId,
                       expectedFrames: c.totalFrames, receivedFrames: c.receivedFrames,
                       expectedPayloadBytes: c.payloadBytes, receivedPayloadBytes: c.receivedBytes,
                       currentSequence: c.currentSequence, missingFrames: c.totalFrames - c.receivedFrames,
                       duplicateFrames: c.duplicateFrames, result: result)
    }
    private func u16(_ b: [UInt8], _ o: Int) -> UInt16? {
        guard o + 1 < b.count else { return nil }; return UInt16(b[o]) | UInt16(b[o + 1]) << 8
    }
    private func u32(_ b: [UInt8], _ o: Int) -> UInt32? {
        guard o + 3 < b.count else { return nil }
        return UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data { crc ^= UInt32(byte); for _ in 0..<8 { crc = crc & 1 != 0 ? crc >> 1 ^ 0xEDB88320 : crc >> 1 } }
        return crc ^ 0xFFFFFFFF
    }
    private func fail(_ message: String) { onStatusChanged?("失败"); onFailure?(message) }
}

extension StopWatchBLEService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let text: String
        switch central.state {
        case .unknown: text = "未知"; case .resetting: text = "正在重置"; case .unsupported: text = "设备不支持 BLE"
        case .unauthorized: text = "蓝牙权限未授权"; case .poweredOff: text = "蓝牙已关闭"; case .poweredOn: text = "蓝牙已打开"
        @unknown default: text = "未知状态"
        }
        onBluetoothStateChanged?(text); onStatusChanged?(central.state == .poweredOn ? "可以开始扫描" : text)
    }
    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        guard peripheral == nil else { return }; peripheral = p; central.stopScan()
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? p.name ?? "未命名设备"
        onDeviceDiscovered?(name, rssi.intValue); onStatusChanged?("已发现设备")
    }
    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        p.delegate = self; onConnectionChanged?(true); onStatusChanged?("已连接，正在发现 Service…")
        p.discoverServices([Self.serviceUUID])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        if streamRequested { failStream("蓝牙连接失败", sendFailure: false) }
        onConnectionChanged?(false); resetConnection(keepPeripheral: true); fail("连接失败：\(error?.localizedDescription ?? "未知错误")")
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool, error: Error?) {
        if streamRequested { failStream("蓝牙连接中断", sendFailure: false) }
        onConnectionChanged?(false); resetConnection(keepPeripheral: false)
        if let error { fail("连接已断开：\(error.localizedDescription)") } else { onStatusChanged?("已断开；可手动重新扫描") }
    }
}

extension StopWatchBLEService: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { fail("发现 Service 失败：\(error.localizedDescription)"); return }
        guard let service = p.services?.first(where: { $0.uuid == Self.serviceUUID }) else { fail("未发现指定 Service"); return }
        p.discoverCharacteristics([Self.commandUUID, Self.responseUUID], for: service)
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { fail("发现 Characteristic 失败：\(error.localizedDescription)"); return }
        for c in service.characteristics ?? [] { if c.uuid == Self.commandUUID { commandCharacteristic = c }; if c.uuid == Self.responseUUID { responseCharacteristic = c } }
        guard let commandCharacteristic, commandCharacteristic.properties.contains(.write) || commandCharacteristic.properties.contains(.writeWithoutResponse) else { fail("Command Characteristic 不可写"); return }
        onWritableChanged?(true)
        guard let responseCharacteristic, responseCharacteristic.properties.contains(.notify) else { fail("Response Characteristic 不支持 Notify"); return }
        p.setNotifyValue(true, for: responseCharacteristic)
    }
    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        if let error { fail("订阅 Notify 失败：\(error.localizedDescription)"); return }
        guard c.uuid == Self.responseUUID else { return }; onSubscriptionChanged?(c.isNotifying)
        onStatusChanged?(c.isNotifying ? "Response Notify 已订阅" : "Response Notify 未订阅")
    }
    func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) {
        if let error { if streamRequested { failStream("写入 Command 失败：\(error.localizedDescription)", sendFailure: false) } else { fail("写入 Command 失败：\(error.localizedDescription)") } }
    }
    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        if let error { if streamRequested { failStream("接收 Notify 失败：\(error.localizedDescription)") } else { fail("接收 Notify 失败：\(error.localizedDescription)") }; return }
        guard c.uuid == Self.responseUUID, let data = c.value else { fail("收到空 Response 数据"); return }
        handleNotify(data)
    }
}
