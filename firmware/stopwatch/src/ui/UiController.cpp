#include <LittleFS.h>
#include <math.h>
#include "UiController.h"

namespace {
constexpr char CHARACTER_ASSET_PATH[] = "/assets/carrot_example.png";
constexpr int32_t CHARACTER_CANVAS_SIZE = 240;
constexpr uint32_t STANDBY_FRAME_INTERVAL_MS = 58;
constexpr float STANDBY_FRONT_PHASE_STEP = 0.025f;
constexpr float STANDBY_MIDDLE_PHASE_STEP = 0.018f;
constexpr float STANDBY_BACK_PHASE_STEP = -0.014f;
constexpr float STANDBY_FRONT_AMPLITUDE = 12.0f;
constexpr float STANDBY_MIDDLE_AMPLITUDE = 9.0f;
constexpr float STANDBY_BACK_AMPLITUDE = 8.0f;
constexpr float STANDBY_FRONT_WAVELENGTH = 168.0f;
constexpr float STANDBY_MIDDLE_WAVELENGTH = 198.0f;
constexpr float STANDBY_BACK_WAVELENGTH = 226.0f;
constexpr float WAVE_TWO_PI = 6.28318530718f;
}

UiController::UiController()
    : standbyCanvas_(&M5.Display), characterCanvas_(&M5.Display) {}

void UiController::begin() {
    M5.Display.setBrightness(96);
    M5.Display.setRotation(0);
    characterAssetReady_ = loadCharacterAsset();
    stateEnteredAt_ = millis();
    Serial.println("[UI] BOOT -> STANDBY");
    dirty_ = true;
    update();
}

void UiController::update() {
    const uint32_t duration = stateDuration(state_);
    if (duration && (uint32_t)(millis() - stateEnteredAt_) >= duration) {
        setState(UiState::StandbyWave);
    }
    if (state_ == UiState::StandbyWave && !dirty_ && M5.Display.width() > 0) {
        const uint32_t now = millis();
        if ((uint32_t)(now - standbyLastFrameAt_) >= STANDBY_FRAME_INTERVAL_MS) {
            drawStandbyWave();
        }
    }
    if (!dirty_ || M5.Display.width() <= 0) return;
    dirty_ = false;
    drawState();
}

void UiController::setState(UiState state) {
    if (state_ == state) return;
    const UiState oldState = state_;
    state_ = state;
    stateEnteredAt_ = millis();
    dirty_ = true;
    Serial.printf("[UI] %s -> %s\n", stateLogText(oldState), stateLogText(state));
}

void UiController::setBleState(UiBleState state) {
    bleState_ = state;
}

void UiController::setLastInput(const char *input) {
    lastInput_ = input;
}

void UiController::setProgress(uint16_t sentFrames, uint16_t totalFrames) {
    sentFrames_ = sentFrames;
    totalFrames_ = totalFrames;
}

void UiController::setError(const char *errorCode) {
    lastError_ = errorCode;
    if (state_ == UiState::Error) {
        stateEnteredAt_ = millis();
        return;
    }
    setState(UiState::Error);
}

const char *UiController::stateText(UiState state) {
    switch (state) {
    case UiState::StandbyWave: return "STANDBY";
    case UiState::Character: return "CHARACTER";
    case UiState::Recording: return "RECORDING";
    case UiState::WaitingAck: return "WAITING ACK";
    case UiState::Saved: return "SAVED";
    case UiState::Error: return "ERROR";
    }
    return "UNKNOWN";
}

const char *UiController::stateLogText(UiState state) {
    switch (state) {
    case UiState::StandbyWave: return "STANDBY";
    case UiState::Character: return "CHARACTER";
    case UiState::Recording: return "RECORDING";
    case UiState::WaitingAck: return "WAITING_ACK";
    case UiState::Saved: return "SAVED";
    case UiState::Error: return "ERROR";
    }
    return "UNKNOWN";
}

uint32_t UiController::stateDuration(UiState state) {
    switch (state) {
    case UiState::Saved: return 1200;
    case UiState::Error: return 2000;
    default: return 0;
    }
}

uint32_t UiController::backgroundColor(UiState state) {
    switch (state) {
    case UiState::StandbyWave: return TFT_BLACK;
    case UiState::Character: return TFT_GREEN;
    case UiState::Recording: return TFT_RED;
    case UiState::WaitingAck: return TFT_BLUE;
    case UiState::Saved: return TFT_WHITE;
    case UiState::Error: return TFT_ORANGE;
    }
    return TFT_BLACK;
}

uint32_t UiController::textColor(UiState state) {
    return state == UiState::Recording || state == UiState::WaitingAck ? TFT_WHITE : TFT_BLACK;
}

bool UiController::loadCharacterAsset() {
    if (!LittleFS.begin(false)) {
        Serial.println("[ASSET] LittleFS mount failed");
        return false;
    }

    Serial.printf("[ASSET] LittleFS mounted: total=%lu used=%lu\n",
                  (unsigned long)LittleFS.totalBytes(),
                  (unsigned long)LittleFS.usedBytes());
    if (!LittleFS.exists(CHARACTER_ASSET_PATH)) {
        Serial.printf("[ASSET] file missing: %s\n", CHARACTER_ASSET_PATH);
        return false;
    }
    File assetFile = LittleFS.open(CHARACTER_ASSET_PATH, "r");
    if (!assetFile) {
        Serial.printf("[ASSET] file open failed: %s\n", CHARACTER_ASSET_PATH);
        return false;
    }
    Serial.printf("[ASSET] file found: %s size=%lu\n",
                  CHARACTER_ASSET_PATH,
                  (unsigned long)assetFile.size());
    assetFile.close();

    characterCanvas_.setColorDepth(16);
    characterCanvas_.setPsram(true);
    if (!characterCanvas_.createSprite(CHARACTER_CANVAS_SIZE, CHARACTER_CANVAS_SIZE)) {
        characterCanvas_.deleteSprite();
        Serial.println("[ASSET] sprite allocation failed");
        return false;
    }

    characterCanvas_.fillScreen(TFT_BLACK);
    constexpr int32_t pngWidth = 216;
    constexpr int32_t pngHeight = 240;
    const int32_t pngX = (CHARACTER_CANVAS_SIZE - pngWidth) / 2;
    const int32_t pngY = (CHARACTER_CANVAS_SIZE - pngHeight) / 2;
    if (!characterCanvas_.drawPngFile(LittleFS, CHARACTER_ASSET_PATH, pngX, pngY)) {
        characterCanvas_.deleteSprite();
        Serial.printf("[ASSET] PNG decode failed: %s\n", CHARACTER_ASSET_PATH);
        return false;
    }

    Serial.println("[ASSET] carrot_example loaded");
    return true;
}

bool UiController::ensureStandbyCanvas() {
    if (standbyCanvasReady_ &&
        standbyCanvas_.width() == M5.Display.width() &&
        standbyCanvas_.height() == M5.Display.height()) {
        return true;
    }

    standbyCanvas_.deleteSprite();
    standbyCanvas_.setColorDepth(16);
    standbyCanvas_.setPsram(true);
    standbyCanvasReady_ = standbyCanvas_.createSprite(M5.Display.width(), M5.Display.height());
    if (!standbyCanvasReady_) {
        Serial.println("[UI] standby canvas allocation failed");
    }
    return standbyCanvasReady_;
}

void UiController::drawWaveLayer(uint16_t color, float phase, float amplitude, float wavelength, float baseYOffset) {
    const int32_t width = standbyCanvas_.width();
    const int32_t height = standbyCanvas_.height();
    const float centerX = (width - 1) * 0.5f;
    const float centerY = (height - 1) * 0.5f;
    const float radius = (width < height ? width : height) * 0.5f - 2.0f;
    const float baseY = height * 0.46f + baseYOffset;
    const float angularFrequency = WAVE_TWO_PI / wavelength;

    for (int32_t x = 0; x < width; ++x) {
        const float dx = x - centerX;
        if (fabsf(dx) > radius) continue;

        const float halfHeight = sqrtf(radius * radius - dx * dx);
        const int32_t topClip = (int32_t)ceilf(centerY - halfHeight);
        const int32_t bottomClip = (int32_t)floorf(centerY + halfHeight);
        const int32_t waveY = (int32_t)roundf(baseY + amplitude * sinf(x * angularFrequency + phase));
        const int32_t y0 = waveY > topClip ? waveY : topClip;
        if (y0 <= bottomClip) {
            standbyCanvas_.drawFastVLine(x, y0, bottomClip - y0 + 1, color);
        }
    }
}

void UiController::drawStandbyWave() {
    if (!ensureStandbyCanvas()) {
        M5.Display.fillScreen(TFT_BLACK);
        return;
    }

    const uint16_t backgroundColor = standbyCanvas_.color565(0, 0, 0);
    const uint16_t frontColor = standbyCanvas_.color565(204, 220, 74);
    const uint16_t middleColor = standbyCanvas_.color565(166, 184, 55);
    const uint16_t backColor = standbyCanvas_.color565(105, 121, 31);

    standbyCanvas_.fillScreen(backgroundColor);
    drawWaveLayer(backColor, standbyBackPhase_, STANDBY_BACK_AMPLITUDE, STANDBY_BACK_WAVELENGTH, 10.0f);
    drawWaveLayer(middleColor, standbyMiddlePhase_, STANDBY_MIDDLE_AMPLITUDE, STANDBY_MIDDLE_WAVELENGTH, 5.0f);
    drawWaveLayer(frontColor, standbyFrontPhase_, STANDBY_FRONT_AMPLITUDE, STANDBY_FRONT_WAVELENGTH, 0.0f);
    standbyCanvas_.pushSprite(0, 0);

    standbyFrontPhase_ += STANDBY_FRONT_PHASE_STEP;
    standbyMiddlePhase_ += STANDBY_MIDDLE_PHASE_STEP;
    standbyBackPhase_ += STANDBY_BACK_PHASE_STEP;
    standbyLastFrameAt_ = millis();
}

void UiController::drawCharacterFrame() {
    const int32_t x = (M5.Display.width() - characterCanvas_.width()) / 2;
    const int32_t y = (M5.Display.height() - characterCanvas_.height()) / 2;
    characterCanvas_.pushSprite(x, y);
}

void UiController::drawState() {
    const UiState state = state_;
    if (state == UiState::StandbyWave) {
        drawStandbyWave();
        return;
    }
    if (state == UiState::Character && characterAssetReady_) {
        M5.Display.startWrite();
        M5.Display.fillScreen(TFT_BLACK);
        drawCharacterFrame();
        M5.Display.endWrite();
        return;
    }
    const uint32_t background = backgroundColor(state);
    M5.Display.startWrite();
    M5.Display.fillScreen(background);
    M5.Display.setTextDatum(middle_center);
    M5.Display.setTextWrap(false);
    M5.Display.setTextSize(3);
    M5.Display.setTextColor(textColor(state), background);
    M5.Display.drawString(stateText(state), M5.Display.width() / 2, M5.Display.height() / 2);
    M5.Display.endWrite();
}
