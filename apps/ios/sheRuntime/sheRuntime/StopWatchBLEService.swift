import Combine
@preconcurrency import CoreBluetooth
import Foundation

@MainActor
final class StopWatchBLEService: NSObject, ObservableObject {
    static let shared = StopWatchBLEService()

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
        var recordingURL: URL?
        var decodedPeak: Int?
        var decodedRMS: Double?
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
    private static let boundPeripheralIDKey = "stopwatch.boundPeripheralID"

    var onBluetoothStateChanged: ((String) -> Void)?
    var onStatusChanged: ((String) -> Void)?
    var onDeviceDiscovered: ((String, Int) -> Void)?
    var onConnectionChanged: ((Bool) -> Void)?
    var onWritableChanged: ((Bool) -> Void)?
    var onSubscriptionChanged: ((Bool) -> Void)?
    var onResponse: ((String, TimeInterval?) -> Void)?
    var onFailure: ((String) -> Void)?
    var onStreamUpdate: ((StreamSnapshot) -> Void)?

    @Published private(set) var bluetoothSystemStatus: StopWatchBluetoothSystemStatus = .notAuthorized
    @Published private(set) var connectionStatus: StopWatchConnectionStatus = .unbound
    @Published private(set) var statusMessage = "等待蓝牙状态"
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var discoveredDeviceName: String?
    @Published private(set) var discoveredRSSI: Int?
    @Published private(set) var boundPeripheralIdentifier: UUID?
    @Published private(set) var lastConnectionDate: Date?
    @Published private(set) var streamSnapshot = StreamSnapshot()

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var responseCharacteristic: CBCharacteristic?
    private var pingSentAt: Date?
    private var stream: StreamContext?
    private var streamRequested = false
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempt = 0
    private var isUserDisconnecting = false
    private var shouldScanWhenPoweredOn = false

    private override init() {
        super.init()
        switch CBCentralManager.authorization {
        case .allowedAlways:
            bluetoothSystemStatus = .authorized
        case .restricted:
            bluetoothSystemStatus = .unsupported
        case .denied, .notDetermined:
            bluetoothSystemStatus = .notAuthorized
        @unknown default:
            bluetoothSystemStatus = .notAuthorized
        }
        if let idString = UserDefaults.standard.string(forKey: Self.boundPeripheralIDKey),
           let uuid = UUID(uuidString: idString) {
            boundPeripheralIdentifier = uuid
            connectionStatus = .disconnected
        }
    }

    func activate() {
        guard centralManager == nil else { return }
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    func activateIfBound() {
        guard boundPeripheralIdentifier != nil else { return }
        activate()
    }
    func startScanning() {
        activate()
        guard centralManager.state == .poweredOn else {
            shouldScanWhenPoweredOn = true
            statusMessage = "等待蓝牙授权或开启"
            onStatusChanged?(statusMessage)
            return
        }
        guard !streamRequested else { fail("流传输期间不能重新扫描"); return }
        shouldScanWhenPoweredOn = false
        isUserDisconnecting = false
        connectionStatus = .scanning
        statusMessage = "正在扫描指定 Service UUID…"
        lastErrorMessage = nil
        resetConnection(keepPeripheral: false)
        onStatusChanged?(statusMessage)
        centralManager.scanForPeripherals(withServices: [Self.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    func stopScanning() { centralManager.stopScan() }
    func connect() {
        activate()
        isUserDisconnecting = false
        reconnectTask?.cancel()
        if let peripheral {
            centralManager.stopScan()
            connectionStatus = .connecting
            statusMessage = "正在连接 \(peripheral.name ?? Self.deviceName)…"
            centralManager.connect(peripheral)
            return
        }
        restoreBoundPeripheralIfPossible(fallbackToScan: true)
    }
    func disconnect() {
        activate()
        isUserDisconnecting = true
        reconnectTask?.cancel()
        centralManager.stopScan()
        guard let peripheral else { onStatusChanged?("当前没有已连接设备"); return }
        centralManager.cancelPeripheralConnection(peripheral)
    }
    func unbind() {
        isUserDisconnecting = true
        reconnectTask?.cancel()
        UserDefaults.standard.removeObject(forKey: Self.boundPeripheralIDKey)
        boundPeripheralIdentifier = nil
        disconnect()
        connectionStatus = .unbound
        statusMessage = "已解除绑定"
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
        if !keepPeripheral {
            discoveredDeviceName = nil
            discoveredRSSI = nil
        }
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
        guard stream == nil else { failStream("重复收到 META"); return }
        guard bytes.count == 14,
              let id = u16(bytes, 1), let frames = u16(bytes, 3),
              let size = u16(bytes, 5), let payload = u32(bytes, 7) else {
            failStream("META 格式错误", sendFailure: false); return
        }
        guard frames == 500, size == 174, payload == 80_000 else {
            failStream("META 参数不符合流协议", sessionId: id); return
        }
        // A physical StopWatch button press starts the stream without an iOS command.
        streamRequested = true
        connectionStatus = .receiving
        let context = StreamContext(sessionId: id, totalFrames: 500, frameSize: 174, payloadBytes: 80_000)
        stream = context; publish(context, active: true, result: "接收中", notifyLength: nil)
        lastErrorMessage = nil
        onStatusChanged?("已收到 META，开始接收真实麦克风 ADPCM 帧…")
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
        let validEnd = endFrames > 0 && endFrames <= context.totalFrames &&
            endPayloadBytes == endFrames * 160
        let completedFrames = validEnd ? Array(context.frames.prefix(endFrames)) : context.frames
        let missing = completedFrames.filter { $0 == nil }.count
        var payload = Data(capacity: endPayloadBytes)
        for frame in completedFrames { if let frame { payload.append(frame) } }
        let actualCRC = Self.crc32(payload)
        let success = validEnd && context.receivedFrames == endFrames && missing == 0 &&
            payload.count == endPayloadBytes && actualCRC == expectedCRC &&
            context.protocolErrors.isEmpty
        var recordingURL: URL?
        var decodedPeak: Int?
        var decodedRMS: Double?
        var fileError: Error?
        if success {
            do {
                let pcm = Self.decodeIMAADPCM(payload, frameBytes: 160)
                let levels = Self.measurePCM(pcm)
                decodedPeak = levels.peak
                decodedRMS = levels.rms
                recordingURL = try Self.writeWAV(pcm: pcm, sampleRate: 16_000, sessionId: context.sessionId)
            } catch { fileError = error }
        }
        let fullySuccessful = success && recordingURL != nil
        let result: String
        if fullySuccessful { result = "成功" }
        else if let fileError { result = "失败：WAV 保存失败（\(fileError.localizedDescription)）" }
        else if let error = context.protocolErrors.first { result = "失败：\(error)" }
        else if missing > 0 { result = "失败：缺失 \(missing) 帧" }
        else if !validEnd { result = "失败：END 帧数或 payload 长度无效" }
        else if payload.count != endPayloadBytes { result = "失败：payload 长度不一致" }
        else if actualCRC != expectedCRC { result = "失败：CRC32 不一致" }
        else { result = "失败：流校验未通过" }
        let elapsed = Date().timeIntervalSince(context.startedAt)
        var snapshot = makeSnapshot(context, active: false, result: result, notifyLength: 174)
        snapshot.expectedFrames = endFrames
        snapshot.expectedPayloadBytes = endPayloadBytes
        snapshot.missingFrames = missing
        snapshot.expectedCRC32 = expectedCRC; snapshot.actualCRC32 = actualCRC
        snapshot.elapsedSeconds = elapsed
        snapshot.speedKBPerSecond = elapsed > 0 ? Double(payload.count) / 1024 / elapsed : nil
        snapshot.recordingURL = recordingURL
        snapshot.decodedPeak = decodedPeak; snapshot.decodedRMS = decodedRMS
        snapshot.confirmationSent = writeCommand("\(fullySuccessful ? "RECEIVED" : "FAILED"):\(context.sessionId)")
        streamSnapshot = snapshot
        lastErrorMessage = fullySuccessful ? nil : result
        onStreamUpdate?(snapshot)
        onStatusChanged?(fullySuccessful ? "流校验成功，WAV 已保存并发送 RECEIVED" : "流校验失败，已发送 FAILED")
        if fullySuccessful { connectionStatus = .connected }
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
        streamSnapshot = snapshot
        lastErrorMessage = snapshot.result
        onStreamUpdate?(snapshot); streamRequested = false; stream = nil
        connectionStatus = peripheral == nil ? .failed : .connected
        onStatusChanged?("麦克风音频流失败")
    }
    private func publish(_ context: StreamContext, active: Bool, result: String, notifyLength: Int?) {
        let snapshot = makeSnapshot(context, active: active, result: result, notifyLength: notifyLength)
        streamSnapshot = snapshot
        onStreamUpdate?(snapshot)
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

    private static let imaStepTable: [Int] = [
        7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31,
        34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143,
        157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544,
        598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878,
        2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894,
        6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818,
        18500, 20350, 22385, 24623, 27086, 29794, 32767
    ]
    private static let imaIndexTable = [-1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8]

    private static func decodeIMAADPCM(_ data: Data, frameBytes: Int) -> [Int16] {
        var pcm: [Int16] = []
        pcm.reserveCapacity(data.count * 2)
        var frameStart = 0
        while frameStart < data.count {
            var predictor = 0
            var stepIndex = 0
            let frameEnd = min(frameStart + frameBytes, data.count)
            for byte in data[frameStart..<frameEnd] {
                for code in [Int(byte & 0x0F), Int(byte >> 4)] {
                    decodeNibble(code, predictor: &predictor, stepIndex: &stepIndex)
                    pcm.append(Int16(predictor))
                }
            }
            frameStart = frameEnd
        }
        return pcm
    }

    private static func decodeNibble(_ code: Int, predictor: inout Int, stepIndex: inout Int) {
        let step = imaStepTable[stepIndex]
        var delta = step >> 3
        if code & 4 != 0 { delta += step }
        if code & 2 != 0 { delta += step >> 1 }
        if code & 1 != 0 { delta += step >> 2 }
        predictor += code & 8 != 0 ? -delta : delta
        predictor = min(32_767, max(-32_768, predictor))
        stepIndex = min(88, max(0, stepIndex + imaIndexTable[code]))
    }

    private static func writeWAV(pcm: [Int16], sampleRate: UInt32, sessionId: UInt16) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("stopwatch-\(sessionId)-\(UUID().uuidString).wav")
        let dataBytes = UInt32(pcm.count * 2)
        var wav = Data()
        func ascii(_ value: String) { wav.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) { wav.append(UInt8(value & 0xFF)); wav.append(UInt8(value >> 8)) }
        func u32(_ value: UInt32) {
            wav.append(UInt8(value & 0xFF)); wav.append(UInt8((value >> 8) & 0xFF))
            wav.append(UInt8((value >> 16) & 0xFF)); wav.append(UInt8(value >> 24))
        }
        ascii("RIFF"); u32(36 + dataBytes); ascii("WAVEfmt "); u32(16); u16(1); u16(1)
        u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16); ascii("data"); u32(dataBytes)
        for sample in pcm { let bits = UInt16(bitPattern: sample); u16(bits) }
        try wav.write(to: url, options: .atomic)
        return url
    }

    private static func measurePCM(_ pcm: [Int16]) -> (peak: Int, rms: Double) {
        guard !pcm.isEmpty else { return (0, 0) }
        var peak = 0
        var sumSquares = 0.0
        for value in pcm {
            let sample = Int(value)
            peak = max(peak, abs(sample))
            sumSquares += Double(sample) * Double(sample)
        }
        return (peak, sqrt(sumSquares / Double(pcm.count)))
    }
    private func fail(_ message: String) {
        statusMessage = "失败"
        lastErrorMessage = message
        onStatusChanged?("失败")
        onFailure?(message)
    }

    private func storeBoundPeripheral(_ id: UUID) {
        boundPeripheralIdentifier = id
        UserDefaults.standard.set(id.uuidString, forKey: Self.boundPeripheralIDKey)
    }

    private func restoreBoundPeripheralIfPossible(fallbackToScan: Bool) {
        guard centralManager.state == .poweredOn else { return }
        guard let boundPeripheralIdentifier else {
            if fallbackToScan { startScanning() }
            return
        }
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [boundPeripheralIdentifier])
        if let recovered = peripherals.first {
            peripheral = recovered
            connectRecoveredPeripheral(recovered)
        } else if fallbackToScan {
            startScanning()
        }
    }

    private func connectRecoveredPeripheral(_ recovered: CBPeripheral) {
        centralManager.stopScan()
        connectionStatus = .connecting
        statusMessage = "正在恢复连接 \(recovered.name ?? Self.deviceName)…"
        onStatusChanged?(statusMessage)
        centralManager.connect(recovered)
    }

    private func scheduleReconnect() {
        guard !isUserDisconnecting else { return }
        guard centralManager.state == .poweredOn else { return }
        reconnectTask?.cancel()
        let delays: [TimeInterval] = [0, 2, 5, 10, 30]
        let delay = delays[min(reconnectAttempt, delays.count - 1)]
        reconnectAttempt = min(reconnectAttempt + 1, delays.count - 1)
        reconnectTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard let self, !Task.isCancelled else { return }
            self.restoreBoundPeripheralIfPossible(fallbackToScan: true)
        }
    }
}

extension StopWatchBLEService: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let text: String
        switch central.state {
        case .unknown:
            text = "未知"
            bluetoothSystemStatus = .notAuthorized
        case .resetting:
            text = "正在重置"
            bluetoothSystemStatus = .notAuthorized
        case .unsupported:
            text = "设备不支持 BLE"
            bluetoothSystemStatus = .unsupported
        case .unauthorized:
            text = "蓝牙权限未授权"
            bluetoothSystemStatus = .notAuthorized
        case .poweredOff:
            text = "蓝牙已关闭"
            bluetoothSystemStatus = .poweredOff
        case .poweredOn:
            text = "蓝牙已打开"
            bluetoothSystemStatus = .authorized
        @unknown default: text = "未知状态"
        }
        onBluetoothStateChanged?(text)
        statusMessage = central.state == .poweredOn ? "可以开始扫描" : text
        onStatusChanged?(statusMessage)
        if central.state == .poweredOff {
            reconnectTask?.cancel()
            shouldScanWhenPoweredOn = false
            connectionStatus = boundPeripheralIdentifier == nil ? .unbound : .disconnected
        }
        if central.state == .poweredOn, shouldScanWhenPoweredOn {
            startScanning()
        } else if central.state == .poweredOn, boundPeripheralIdentifier != nil {
            restoreBoundPeripheralIfPossible(fallbackToScan: true)
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        guard peripheral == nil else { return }
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? p.name ?? "未命名设备"
        guard name == Self.deviceName else { return }
        peripheral = p
        discoveredRSSI = rssi.intValue
        central.stopScan()
        discoveredDeviceName = name
        onDeviceDiscovered?(name, rssi.intValue)
        statusMessage = "已发现设备"
        onStatusChanged?(statusMessage)
        connectionStatus = .connecting
        central.connect(p)
    }
    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        reconnectAttempt = 0
        p.delegate = self
        onConnectionChanged?(true)
        statusMessage = "已连接，正在发现 Service…"
        onStatusChanged?(statusMessage)
        connectionStatus = .connected
        lastConnectionDate = Date()
        storeBoundPeripheral(p.identifier)
        p.discoverServices([Self.serviceUUID])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        if streamRequested { failStream("蓝牙连接失败", sendFailure: false) }
        onConnectionChanged?(false)
        connectionStatus = .failed
        resetConnection(keepPeripheral: true)
        fail("连接失败：\(error?.localizedDescription ?? "未知错误")")
        if !isUserDisconnecting { scheduleReconnect() }
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool, error: Error?) {
        if streamRequested { failStream("蓝牙连接中断", sendFailure: false) }
        onConnectionChanged?(false)
        resetConnection(keepPeripheral: false)
        if isUserDisconnecting {
            connectionStatus = boundPeripheralIdentifier == nil ? .unbound : .disconnected
            statusMessage = "已断开；可手动重新扫描"
            onStatusChanged?(statusMessage)
        } else {
            connectionStatus = .disconnected
            statusMessage = error.map { "连接已断开：\($0.localizedDescription)" } ?? "已断开，正在尝试恢复"
            onStatusChanged?(statusMessage)
            scheduleReconnect()
        }
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
        guard c.uuid == Self.responseUUID else { return }
        onSubscriptionChanged?(c.isNotifying)
        statusMessage = c.isNotifying ? "Response Notify 已订阅" : "Response Notify 未订阅"
        onStatusChanged?(statusMessage)
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
