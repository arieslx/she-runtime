#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

static const char *DEVICE_NAME = "sheRuntime-StopWatch";
static const char *SERVICE_UUID = "a7f00001-4d7a-4e6b-9f30-6a8e2a14c001";
static const char *COMMAND_UUID = "a7f00002-4d7a-4e6b-9f30-6a8e2a14c001";
static const char *RESPONSE_UUID = "a7f00003-4d7a-4e6b-9f30-6a8e2a14c001";
static constexpr uint16_t REQUESTED_MTU = 247, MINIMUM_MTU = 177;
static constexpr uint16_t TOTAL_FRAMES = 500, FRAME_SIZE = 174, PAYLOAD_SIZE = 160;
static constexpr uint32_t TOTAL_PAYLOAD_BYTES = 80000, FRAME_INTERVAL_MS = 20, CONFIRM_TIMEOUT_MS = 5000;

enum class Phase : uint8_t { IDLE, PREPARE, META, AUDIO, END, WAIT_CONFIRM };
struct StreamState {
    volatile bool active = false, startRequested = false, abortRequested = false;
    volatile bool confirmReceived = false, notifyError = false;
    Phase phase = Phase::IDLE;
    uint16_t sessionId = 0, sequence = 0;
    uint32_t crc32 = 0, nextFrameAt = 0, confirmDeadline = 0;
    uint32_t notifyCount = 0, maxNotifyMicros = 0;
    uint64_t totalNotifyMicros = 0;
};

static BLECharacteristic *responseCharacteristic = nullptr;
static BLE2902 *responseCCCD = nullptr;
static volatile bool connected = false;
static volatile uint16_t negotiatedMTU = 23, connectionIntervalUnits = 0;
static uint8_t packet[FRAME_SIZE];
static uint16_t nextSessionId = 1;
static StreamState stream;

static void put16(uint8_t *p, uint16_t v) { p[0] = v; p[1] = v >> 8; }
static void put32(uint8_t *p, uint32_t v) {
    p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24;
}
static uint32_t crcUpdate(uint32_t crc, const uint8_t *data, size_t length) {
    for (size_t i = 0; i < length; ++i) {
        crc ^= data[i];
        for (uint8_t bit = 0; bit < 8; ++bit) crc = (crc & 1) ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
    return crc;
}
static uint32_t expectedCRC() {
    uint32_t crc = 0xFFFFFFFF;
    uint8_t payload[PAYLOAD_SIZE];
    for (uint16_t seq = 0; seq < TOTAL_FRAMES; ++seq) {
        for (uint16_t i = 0; i < PAYLOAD_SIZE; ++i) payload[i] = (seq * PAYLOAD_SIZE + i) % 256;
        crc = crcUpdate(crc, payload, sizeof(payload));
    }
    return crc ^ 0xFFFFFFFF;
}

class ResponseCallbacks : public BLECharacteristicCallbacks {
    void onStatus(BLECharacteristic *, Status status, uint32_t code) override {
        if (status != SUCCESS_NOTIFY) {
            stream.notifyError = true;
            Serial.printf("Notify status error: status=%d code=%lu\n", status, (unsigned long)code);
        }
    }
};
static bool notifyBinary(const uint8_t *data, size_t length) {
    if (!connected || !responseCCCD || !responseCCCD->getNotifications()) {
        Serial.println("Notify rejected: disconnected or CCCD disabled."); return false;
    }
    if (negotiatedMTU < MINIMUM_MTU || length > negotiatedMTU - 3) {
        Serial.printf("Notify rejected: MTU %u cannot carry %u bytes.\n", negotiatedMTU, (unsigned)length);
        return false;
    }
    stream.notifyError = false;
    uint32_t started = micros();
    responseCharacteristic->setValue(const_cast<uint8_t *>(data), length);
    responseCharacteristic->notify();
    uint32_t elapsed = micros() - started;
    ++stream.notifyCount; stream.totalNotifyMicros += elapsed;
    stream.maxNotifyMicros = max(stream.maxNotifyMicros, elapsed);
    return !stream.notifyError;
}
static bool notifyText(const char *text) {
    if (!connected || !responseCCCD || !responseCCCD->getNotifications()) return false;
    responseCharacteristic->setValue((uint8_t *)text, strlen(text));
    responseCharacteristic->notify();
    return true;
}
static void resetStream() {
    stream.active = stream.startRequested = stream.abortRequested = false;
    stream.confirmReceived = stream.notifyError = false;
    stream.phase = Phase::IDLE; stream.sequence = 0;
}
static void abortStream(const char *reason) {
    Serial.printf("Stream %u aborted: %s\n", stream.sessionId, reason); resetStream();
}
static void prepareStream() {
    stream.sessionId = nextSessionId++; if (!nextSessionId) nextSessionId = 1;
    stream.crc32 = expectedCRC(); stream.sequence = 0;
    stream.notifyCount = stream.maxNotifyMicros = 0; stream.totalNotifyMicros = 0;
    stream.phase = Phase::META;
    Serial.printf("Stream start: session=%u frames=%u frameSize=%u payload=%lu CRC=0x%08lX MTU=%u interval=%.2fms\n",
                  stream.sessionId, TOTAL_FRAMES, FRAME_SIZE, (unsigned long)TOTAL_PAYLOAD_BYTES,
                  (unsigned long)stream.crc32, negotiatedMTU, connectionIntervalUnits * 1.25f);
}
static bool sendMeta() {
    memset(packet, 0, 14); packet[0] = 0x20;
    put16(packet + 1, stream.sessionId); put16(packet + 3, TOTAL_FRAMES); put16(packet + 5, FRAME_SIZE);
    put32(packet + 7, TOTAL_PAYLOAD_BYTES); return notifyBinary(packet, 14);
}
static bool sendAudio(uint16_t seq) {
    put16(packet, seq); packet[2] = 0x01; packet[3] = 0;
    put32(packet + 4, (uint32_t)seq * 320); put16(packet + 8, 320); put16(packet + 10, 0);
    packet[12] = packet[13] = 0;
    for (uint16_t i = 0; i < PAYLOAD_SIZE; ++i) packet[14 + i] = (seq * PAYLOAD_SIZE + i) % 256;
    return notifyBinary(packet, FRAME_SIZE);
}
static bool sendEnd() {
    packet[0] = 0x22; put16(packet + 1, stream.sessionId); put16(packet + 3, TOTAL_FRAMES);
    put32(packet + 5, TOTAL_PAYLOAD_BYTES); put32(packet + 9, stream.crc32);
    return notifyBinary(packet, 13);
}
static void processStream() {
    if (stream.abortRequested) { abortStream("disconnect, peer failure, or notify error"); return; }
    if (stream.startRequested && stream.phase == Phase::PREPARE) {
        stream.startRequested = false; prepareStream();
    }
    if (!stream.active || stream.phase == Phase::IDLE) return;
    switch (stream.phase) {
    case Phase::META:
        if (!sendMeta()) { abortStream("META notify failed"); return; }
        stream.nextFrameAt = millis() + FRAME_INTERVAL_MS; stream.phase = Phase::AUDIO; break;
    case Phase::AUDIO: {
        uint32_t now = millis(); if ((int32_t)(now - stream.nextFrameAt) < 0) return;
        if (stream.sequence % 50 == 0 || stream.sequence == TOTAL_FRAMES - 1)
            Serial.printf("Stream progress: %u/%u\n", stream.sequence, TOTAL_FRAMES - 1);
        if (!sendAudio(stream.sequence)) { abortStream("AUDIO notify failed"); return; }
        ++stream.sequence; stream.nextFrameAt = now + FRAME_INTERVAL_MS;
        if (stream.sequence >= TOTAL_FRAMES) stream.phase = Phase::END;
        break;
    }
    case Phase::END:
        if (!sendEnd()) { abortStream("END notify failed"); return; }
        Serial.printf("END sent. Notify calls=%lu average=%llu us max=%lu us\n",
                      (unsigned long)stream.notifyCount,
                      stream.notifyCount ? stream.totalNotifyMicros / stream.notifyCount : 0,
                      (unsigned long)stream.maxNotifyMicros);
        stream.confirmDeadline = millis() + CONFIRM_TIMEOUT_MS; stream.phase = Phase::WAIT_CONFIRM; break;
    case Phase::WAIT_CONFIRM:
        if (stream.confirmReceived) { Serial.printf("RECEIVED confirmed: session=%u\n", stream.sessionId); resetStream(); }
        else if ((int32_t)(millis() - stream.confirmDeadline) >= 0) abortStream("confirmation timeout");
        break;
    default: break;
    }
}

static void gapHandler(esp_gap_ble_cb_event_t event, esp_ble_gap_cb_param_t *p) {
    if (event == ESP_GAP_BLE_UPDATE_CONN_PARAMS_EVT) {
        connectionIntervalUnits = p->update_conn_params.conn_int;
        Serial.printf("Connection params: status=%d interval=%.2fms latency=%u timeout=%u\n",
                      p->update_conn_params.status, connectionIntervalUnits * 1.25f,
                      p->update_conn_params.latency, p->update_conn_params.timeout);
    }
}
class ServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer *server, esp_ble_gatts_cb_param_t *p) override {
        connected = true; negotiatedMTU = server->getPeerMTU(p->connect.conn_id);
        server->updateConnParams(p->connect.remote_bda, 12, 12, 0, 400);
        Serial.printf("BLE connected; initial MTU=%u; requested interval=15ms.\n", negotiatedMTU);
    }
    void onMtuChanged(BLEServer *, esp_ble_gatts_cb_param_t *p) override {
        negotiatedMTU = p->mtu.mtu;
        Serial.printf("Negotiated ATT MTU=%u (%s).\n", negotiatedMTU,
                      negotiatedMTU >= MINIMUM_MTU ? "174-byte Notify supported" : "insufficient");
    }
    void onDisconnect(BLEServer *) override {
        connected = false; negotiatedMTU = 23; connectionIntervalUnits = 0;
        if (stream.active) stream.abortRequested = true;
        BLEDevice::startAdvertising(); Serial.println("BLE disconnected; advertising restored.");
    }
};
class CommandCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *c) override {
        std::string command = c->getValue(); Serial.printf("Command: %s\n", command.c_str());
        if (command == "ping") {
            if (notifyText("pong")) Serial.println("Response: pong");
        } else if (command == "START_STREAM_TEST") {
            if (stream.active) Serial.println("START_STREAM_TEST rejected: session active.");
            else if (!connected || !responseCCCD || !responseCCCD->getNotifications())
                Serial.println("START_STREAM_TEST rejected: Notify unavailable.");
            else if (negotiatedMTU < MINIMUM_MTU)
                Serial.printf("START_STREAM_TEST rejected: MTU %u below %u.\n", negotiatedMTU, MINIMUM_MTU);
            else { stream.active = stream.startRequested = true; stream.phase = Phase::PREPARE; }
        } else if (command.rfind("RECEIVED:", 0) == 0 || command.rfind("FAILED:", 0) == 0) {
            bool ok = command.rfind("RECEIVED:", 0) == 0;
            uint16_t id = strtoul(command.c_str() + (ok ? 9 : 7), nullptr, 10);
            Serial.printf("Confirmation: %s session=%u\n", ok ? "RECEIVED" : "FAILED", id);
            if (stream.active && id == stream.sessionId && ok && stream.phase == Phase::WAIT_CONFIRM)
                stream.confirmReceived = true;
            else if (stream.active && id == stream.sessionId) stream.abortRequested = true;
        }
    }
};
static void initializeBLE() {
    BLEDevice::init(DEVICE_NAME);
    Serial.printf("Local MTU request %u result=%d\n", REQUESTED_MTU, BLEDevice::setMTU(REQUESTED_MTU));
    BLEDevice::setCustomGapHandler(gapHandler);
    BLEServer *server = BLEDevice::createServer(); server->setCallbacks(new ServerCallbacks());
    BLEService *service = server->createService(SERVICE_UUID);
    BLECharacteristic *command = service->createCharacteristic(COMMAND_UUID, BLECharacteristic::PROPERTY_WRITE);
    command->setCallbacks(new CommandCallbacks());
    responseCharacteristic = service->createCharacteristic(RESPONSE_UUID, BLECharacteristic::PROPERTY_NOTIFY);
    responseCharacteristic->setCallbacks(new ResponseCallbacks()); responseCCCD = new BLE2902();
    responseCharacteristic->addDescriptor(responseCCCD); service->start();
    BLEAdvertising *advertising = BLEDevice::getAdvertising(); advertising->addServiceUUID(SERVICE_UUID);
    advertising->setScanResponse(true); BLEDevice::startAdvertising();
}
void setup() {
    Serial.begin(115200); delay(1000); Serial.println("Starting simulated ADPCM BLE stream probe...");
    initializeBLE();
}
void loop() { processStream(); delay(1); }
