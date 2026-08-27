#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <M5Unified.h>
#include "ui/UiController.h"

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
    volatile bool stopRequested = false;
    volatile bool confirmReceived = false, notifyError = false;
    Phase phase = Phase::IDLE;
    uint16_t sessionId = 0, sequence = 0;
    uint32_t crc32 = 0, nextFrameAt = 0, confirmDeadline = 0;
    uint32_t notifyCount = 0, maxNotifyMicros = 0;
    uint64_t totalNotifyMicros = 0;
    int16_t pcmMin = 32767, pcmMax = -32768;
    uint32_t pcmPeak = 0;
    uint64_t pcmSumSquares = 0;
    uint32_t pcmSamples = 0, pcmZeros = 0;
    bool capturePending = false;
};

static BLECharacteristic *responseCharacteristic = nullptr;
static BLE2902 *responseCCCD = nullptr;
static volatile bool connected = false;
static volatile uint16_t negotiatedMTU = 23, connectionIntervalUnits = 0;
static uint8_t packet[FRAME_SIZE];
static uint16_t nextSessionId = 1;
static StreamState stream;
static int16_t pcmFrame[320];
static uint32_t vibrationUntil = 0;
static bool microphoneReady = false;
static UiController ui;

static const int16_t IMA_STEP_TABLE[89] = {
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31,
    34, 37, 41, 45, 50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143,
    157, 173, 190, 209, 230, 253, 279, 307, 337, 371, 408, 449, 494, 544,
    598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878,
    2066, 2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894,
    6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899, 15289, 16818,
    18500, 20350, 22385, 24623, 27086, 29794, 32767
};
static const int8_t IMA_INDEX_TABLE[16] = {
    -1, -1, -1, -1, 2, 4, 6, 8, -1, -1, -1, -1, 2, 4, 6, 8
};

// Each BLE frame is independently decodable: predictor and step index reset to zero.
static void encodeIMAADPCM(const int16_t *samples, uint8_t *output) {
    int predictor = 0, stepIndex = 0;
    for (uint16_t i = 0; i < 320; ++i) {
        int step = IMA_STEP_TABLE[stepIndex];
        int diff = (int)samples[i] - predictor;
        uint8_t code = diff < 0 ? 8 : 0;
        if (diff < 0) diff = -diff;
        int delta = step >> 3;
        if (diff >= step) { code |= 4; diff -= step; delta += step; }
        if (diff >= (step >> 1)) { code |= 2; diff -= step >> 1; delta += step >> 1; }
        if (diff >= (step >> 2)) { code |= 1; delta += step >> 2; }
        predictor += (code & 8) ? -delta : delta;
        predictor = constrain(predictor, -32768, 32767);
        stepIndex = constrain(stepIndex + IMA_INDEX_TABLE[code], 0, 88);
        if (i & 1) output[i >> 1] |= code << 4;
        else output[i >> 1] = code;
    }
}

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
class ResponseCallbacks : public BLECharacteristicCallbacks {
    void onStatus(BLECharacteristic *, Status status, uint32_t code) override {
        if (status != SUCCESS_NOTIFY) {
            stream.notifyError = true;
            ui.setError("NOTIFY_FAIL");
            Serial.printf("Notify status error: status=%d code=%lu\n", status, (unsigned long)code);
        }
    }
};
static bool notifyBinary(const uint8_t *data, size_t length) {
    if (!connected || !responseCCCD || !responseCCCD->getNotifications()) {
        ui.setError(connected ? "NOTIFY_NOT_READY" : "BLE_NOT_CONNECTED");
        Serial.println("Notify rejected: disconnected or CCCD disabled."); return false;
    }
    if (negotiatedMTU < MINIMUM_MTU || length > negotiatedMTU - 3) {
        ui.setError("MTU_TOO_SMALL");
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
    stream.stopRequested = false;
    stream.confirmReceived = stream.notifyError = false;
    stream.phase = Phase::IDLE; stream.sequence = 0; stream.capturePending = false;
    while (M5.Mic.isRecording()) delay(1);
}
static void abortStream(const char *reason, const char *errorCode = "STREAM_ABORT") {
    ui.setError(errorCode);
    Serial.printf("Stream %u aborted: %s\n", stream.sessionId, reason); resetStream();
}
static void prepareStream() {
    stream.sessionId = nextSessionId++; if (!nextSessionId) nextSessionId = 1;
    stream.crc32 = 0xFFFFFFFF; stream.sequence = 0; stream.capturePending = false;
    stream.notifyCount = stream.maxNotifyMicros = 0; stream.totalNotifyMicros = 0;
    stream.pcmMin = 32767; stream.pcmMax = -32768; stream.pcmPeak = 0;
    stream.pcmSumSquares = 0; stream.pcmSamples = stream.pcmZeros = 0;
    ui.setProgress(0, TOTAL_FRAMES);
    stream.phase = Phase::META;
    ui.setState(UiState::Recording);
    Serial.printf("Stream start: session=%u frames=%u frameSize=%u payload=%lu MTU=%u interval=%.2fms\n",
                  stream.sessionId, TOTAL_FRAMES, FRAME_SIZE, (unsigned long)TOTAL_PAYLOAD_BYTES,
                  negotiatedMTU, connectionIntervalUnits * 1.25f);
}
static bool sendMeta() {
    memset(packet, 0, 14); packet[0] = 0x20;
    put16(packet + 1, stream.sessionId); put16(packet + 3, TOTAL_FRAMES); put16(packet + 5, FRAME_SIZE);
    put32(packet + 7, TOTAL_PAYLOAD_BYTES); return notifyBinary(packet, 14);
}
static bool sendAudio(uint16_t seq, const uint8_t *payload) {
    put16(packet, seq); packet[2] = 0x01; packet[3] = 0;
    put32(packet + 4, (uint32_t)seq * 320); put16(packet + 8, 320); put16(packet + 10, 0);
    packet[12] = packet[13] = 0;
    memcpy(packet + 14, payload, PAYLOAD_SIZE);
    return notifyBinary(packet, FRAME_SIZE);
}
static bool sendEnd() {
    packet[0] = 0x22; put16(packet + 1, stream.sessionId); put16(packet + 3, stream.sequence);
    put32(packet + 5, (uint32_t)stream.sequence * PAYLOAD_SIZE); put32(packet + 9, stream.crc32);
    return notifyBinary(packet, 13);
}
static void processStream() {
    if (stream.abortRequested) {
        abortStream("disconnect, peer failure, or notify error", connected ? "NOTIFY_FAIL" : "BLE_NOT_CONNECTED");
        return;
    }
    if (stream.startRequested && stream.phase == Phase::PREPARE) {
        stream.startRequested = false; prepareStream();
    }
    if (!stream.active || stream.phase == Phase::IDLE) return;
    switch (stream.phase) {
    case Phase::META:
        if (!sendMeta()) { abortStream("META notify failed", "NOTIFY_FAIL"); return; }
        stream.phase = Phase::AUDIO; break;
    case Phase::AUDIO: {
        if (!stream.capturePending) {
            if (!M5.Mic.record(pcmFrame, 320, 16000, false)) {
                abortStream("microphone capture queue failed", "MIC_CAPTURE_FAIL"); return;
            }
            stream.capturePending = true;
            return;
        }
        if (M5.Mic.isRecording()) return;
        stream.capturePending = false;
        int16_t frameMin = 32767, frameMax = -32768;
        uint32_t framePeak = 0;
        uint64_t frameSumSquares = 0;
        for (uint16_t i = 0; i < 320; ++i) {
            int32_t sample = pcmFrame[i];
            frameMin = min(frameMin, pcmFrame[i]); frameMax = max(frameMax, pcmFrame[i]);
            uint32_t magnitude = sample < 0 ? (uint32_t)-sample : (uint32_t)sample;
            framePeak = max(framePeak, magnitude);
            frameSumSquares += (int64_t)sample * sample;
            if (sample == 0) ++stream.pcmZeros;
        }
        stream.pcmMin = min(stream.pcmMin, frameMin); stream.pcmMax = max(stream.pcmMax, frameMax);
        stream.pcmPeak = max(stream.pcmPeak, framePeak);
        stream.pcmSumSquares += frameSumSquares; stream.pcmSamples += 320;
        uint8_t payload[PAYLOAD_SIZE];
        encodeIMAADPCM(pcmFrame, payload);
        if (stream.sequence % 50 == 0 || stream.sequence == TOTAL_FRAMES - 1) {
            double frameRMS = sqrt((double)frameSumSquares / 320.0);
            Serial.printf("Stream progress: %u/%u PCM[min=%d max=%d peak=%lu rms=%.1f]\n",
                          stream.sequence, TOTAL_FRAMES - 1, frameMin, frameMax,
                          (unsigned long)framePeak, frameRMS);
        }
        if (!sendAudio(stream.sequence, payload)) { abortStream("AUDIO notify failed", "NOTIFY_FAIL"); return; }
        stream.crc32 = crcUpdate(stream.crc32, payload, sizeof(payload));
        ++stream.sequence;
        if (stream.sequence % 20 == 0 || stream.sequence == TOTAL_FRAMES) {
            ui.setProgress(stream.sequence, TOTAL_FRAMES);
        }
        if (stream.stopRequested || stream.sequence >= TOTAL_FRAMES) {
            if (stream.stopRequested) {
                Serial.printf("Manual stop accepted after frame %u.\n", stream.sequence);
                ui.setProgress(stream.sequence, stream.sequence);
            }
            stream.phase = Phase::END;
        }
        break;
    }
    case Phase::END:
        stream.crc32 ^= 0xFFFFFFFF;
        if (!sendEnd()) { abortStream("END notify failed", "NOTIFY_FAIL"); return; }
        Serial.printf("END sent. Notify calls=%lu average=%llu us max=%lu us\n",
                      (unsigned long)stream.notifyCount,
                      stream.notifyCount ? stream.totalNotifyMicros / stream.notifyCount : 0,
                      (unsigned long)stream.maxNotifyMicros);
        Serial.printf("PCM summary: samples=%lu min=%d max=%d peak=%lu rms=%.1f zeros=%lu (%.2f%%)\n",
                      (unsigned long)stream.pcmSamples, stream.pcmMin, stream.pcmMax,
                      (unsigned long)stream.pcmPeak,
                      stream.pcmSamples ? sqrt((double)stream.pcmSumSquares / stream.pcmSamples) : 0.0,
                      (unsigned long)stream.pcmZeros,
                      stream.pcmSamples ? 100.0 * stream.pcmZeros / stream.pcmSamples : 0.0);
        stream.confirmDeadline = millis() + CONFIRM_TIMEOUT_MS; stream.phase = Phase::WAIT_CONFIRM;
        ui.setState(UiState::WaitingAck); break;
    case Phase::WAIT_CONFIRM:
        if (stream.confirmReceived) {
            Serial.printf("Real microphone stream succeeded: RECEIVED confirmed session=%u\n", stream.sessionId);
            ui.setState(UiState::Saved);
            M5.Power.setVibration(128); vibrationUntil = millis() + 120;
            resetStream();
        }
        else if ((int32_t)(millis() - stream.confirmDeadline) >= 0)
            abortStream("confirmation timeout", "ACK_TIMEOUT");
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
        ui.setBleState(UiBleState::Connected);
        server->updateConnParams(p->connect.remote_bda, 12, 12, 0, 400);
        Serial.printf("BLE connected; initial MTU=%u; requested interval=15ms.\n", negotiatedMTU);
    }
    void onMtuChanged(BLEServer *, esp_ble_gatts_cb_param_t *p) override {
        negotiatedMTU = p->mtu.mtu;
        ui.setBleState(UiBleState::Connected);
        Serial.printf("Negotiated ATT MTU=%u (%s).\n", negotiatedMTU,
                      negotiatedMTU >= MINIMUM_MTU ? "174-byte Notify supported" : "insufficient");
    }
    void onDisconnect(BLEServer *) override {
        connected = false; negotiatedMTU = 23; connectionIntervalUnits = 0;
        if (stream.active) stream.abortRequested = true;
        ui.setBleState(UiBleState::Advertising);
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
            else if (!connected || !responseCCCD || !responseCCCD->getNotifications()) {
                ui.setError(connected ? "NOTIFY_NOT_READY" : "BLE_NOT_CONNECTED");
                Serial.println("START_STREAM_TEST rejected: Notify unavailable.");
            } else if (negotiatedMTU < MINIMUM_MTU) {
                ui.setError("MTU_TOO_SMALL");
                Serial.printf("START_STREAM_TEST rejected: MTU %u below %u.\n", negotiatedMTU, MINIMUM_MTU);
            } else { stream.active = stream.startRequested = true; stream.phase = Phase::PREPARE; }
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
    ui.setBleState(UiBleState::Advertising);
}
void setup() {
    Serial.begin(115200); delay(1000); Serial.println("Starting real microphone ADPCM BLE stream probe...");
    auto cfg = M5.config();
    M5.begin(cfg);
    Serial.printf("M5 board=%d display=%dx%d\n", (int)M5.getBoard(), M5.Display.width(), M5.Display.height());
    if (M5.getBoard() != m5::board_t::board_M5StopWatch)
        Serial.println("WARNING: M5Unified did not identify board_M5StopWatch.");
    ui.begin();
    M5.Speaker.end();
    auto micConfig = M5.Mic.config();
    micConfig.sample_rate = 16000; micConfig.over_sampling = 1;
    micConfig.dma_buf_len = 320; micConfig.dma_buf_count = 4;
    M5.Mic.config(micConfig);
    if (!M5.Mic.begin()) {
        ui.setError("MIC_INIT_FAIL");
        Serial.println("WARNING: microphone initialization failed.");
    } else {
        microphoneReady = true;
        ui.setState(UiState::StandbyWave);
    }
    initializeBLE();
    ui.update();
}
void loop() {
    M5.update();
    UiBleState currentBLEStatus = connected
        ? ((responseCCCD && responseCCCD->getNotifications() && negotiatedMTU >= MINIMUM_MTU)
            ? UiBleState::Ready : UiBleState::Connected)
        : UiBleState::Advertising;
    static UiBleState lastBLEStatus = UiBleState::Booting;
    if (lastBLEStatus != currentBLEStatus) {
        lastBLEStatus = currentBLEStatus;
        ui.setBleState(currentBLEStatus);
    }
    bool buttonA = M5.BtnA.wasClicked();
    bool buttonPower = M5.BtnPWR.wasClicked();
    bool screenTapped = M5.Touch.getCount() && M5.Touch.getDetail(0).wasClicked();
    if (buttonA) {
        ui.setLastInput("BUTTON_A");
        Serial.printf("Button event: BUTTON_A connected=%d notify=%d mtu=%u mic=%d\n",
                      connected, responseCCCD && responseCCCD->getNotifications(), negotiatedMTU, microphoneReady);
    }
    if (buttonPower) {
        ui.setLastInput("BUTTON_PWR");
        Serial.println("Button event: BUTTON_PWR (recording disabled during probe)");
    }
    if (screenTapped) {
        if (ui.state() == UiState::StandbyWave) ui.setState(UiState::Character);
        else if (ui.state() == UiState::Character) ui.setState(UiState::StandbyWave);
        else Serial.printf("Touch ignored in %u.\n", (unsigned)ui.state());
    }
    // BtnPWR is intentionally display/log-only during probe because it also controls device power.
    const UiState currentUiState = ui.state();
    if (stream.active && buttonA) {
        if (currentUiState == UiState::Recording &&
            (stream.phase == Phase::PREPARE || stream.phase == Phase::META || stream.phase == Phase::AUDIO) &&
            !stream.stopRequested) {
            stream.stopRequested = true;
            Serial.printf("Button stop requested: session=%u phase=%u frames=%u\n",
                          stream.sessionId, (unsigned)stream.phase, stream.sequence);
        } else {
            Serial.printf("Button stop ignored: session=%u already waiting for ACK.\n", stream.sessionId);
        }
    } else if (!stream.active && buttonA &&
               (currentUiState == UiState::StandbyWave || currentUiState == UiState::Character)) {
        bool notifySubscribed = responseCCCD && responseCCCD->getNotifications();
        if (!connected || !notifySubscribed) {
            ui.setError(connected ? "NOTIFY_NOT_READY" : "BLE_NOT_CONNECTED");
            if (connected) ui.setBleState(UiBleState::Connected);
            Serial.println("Button start rejected: BLE Notify unavailable.");
        } else if (negotiatedMTU < MINIMUM_MTU) {
            ui.setError("MTU_TOO_SMALL");
            Serial.printf("Button start rejected: MTU %u below %u.\n", negotiatedMTU, MINIMUM_MTU);
        } else {
            stream.active = stream.startRequested = true; stream.phase = Phase::PREPARE;
        }
    } else if (buttonA) {
        Serial.printf("Button ignored in UI state %u.\n", (unsigned)currentUiState);
    }
    processStream();
    ui.update();
    if (vibrationUntil && (int32_t)(millis() - vibrationUntil) >= 0) {
        M5.Power.setVibration(0); vibrationUntil = 0;
    }
    delay(1);
}
