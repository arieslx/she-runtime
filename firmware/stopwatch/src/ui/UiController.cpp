#include <LittleFS.h>
#include <math.h>
#include "UiController.h"

namespace {
constexpr int32_t CHARACTER_CANVAS_SIZE = 180;
constexpr char ERROR_ASSET_PATH[] = "/assets/mascot_sleep.png";
constexpr int32_t ERROR_CANVAS_WIDTH = 200;
constexpr int32_t ERROR_CANVAS_HEIGHT = 190;
constexpr int32_t ERROR_ASSET_WIDTH = 190;
constexpr int32_t ERROR_ASSET_HEIGHT = 180;
constexpr uint32_t STANDBY_FRAME_INTERVAL_MS = 88;
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
constexpr uint32_t RECORDING_FRAME_INTERVAL_MS = 66;
constexpr float RECORDING_BARS_PHASE_STEP = 0.13f;

constexpr EnergyTierStyle ENERGY_STYLES[] = {
    {"低", "先把恢复放在第一位", "/assets/mascot_t1.png", 165, 155, 22, 240,
     232, 131, 126, 151, 88, 75, 91, 52, 46},
    {"偏低", "放慢节奏，减少消耗", "/assets/mascot_t2.png", 160, 165, 36, 300,
     240, 154, 107, 157, 101, 72, 94, 61, 46},
    {"平稳", "保持当前节奏", "/assets/mascot_t3.png", 133, 165, 50, 0,
     192, 226, 144, 151, 181, 91, 91, 110, 55},
    {"良好", "适合推进重要任务", "/assets/mascot_t4.png", 146, 165, 66, 60,
     143, 210, 74, 105, 160, 54, 62, 98, 32},
    {"充沛", "进入深度工作窗口", "/assets/mascot_t5.png", 117, 165, 80, 120,
     104, 195, 0, 78, 145, 12, 44, 86, 8},
};

constexpr uint8_t tierIndex(EnergyTier tier) {
    return static_cast<uint8_t>(tier);
}

const EnergyTierStyle &styleFor(EnergyTier tier) {
    return ENERGY_STYLES[tierIndex(tier)];
}
}

UiController::UiController()
    : standbyCanvas_(&M5.Display), recordingCanvas_(&M5.Display), errorCanvas_(&M5.Display) {}

void UiController::begin() {
    M5.Display.setBrightness(96);
    M5.Display.setRotation(0);
    loadCharacterAssets();
    stateEnteredAt_ = millis();
    Serial.println("[UI] BOOT -> STANDBY");
    dirty_ = true;
    update();
}

void UiController::cycleEnergyTier() {
    if (state_ != UiState::StandbyWave && state_ != UiState::Character) return;
    const uint8_t next = (tierIndex(energyTier_) + 1) % tierIndex(EnergyTier::Count);
    energyTier_ = static_cast<EnergyTier>(next);
    dirty_ = true;
    Serial.printf("[UI] energy tier -> %u (%s)\n", next + 1, styleFor(energyTier_).label);
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
    if (state_ == UiState::Recording && !recordingVisualFrozen_ && !dirty_ && M5.Display.width() > 0) {
        const uint32_t now = millis();
        if ((uint32_t)(now - recordingLastFrameAt_) >= RECORDING_FRAME_INTERVAL_MS) {
            recordingBarsPhase_ += RECORDING_BARS_PHASE_STEP;
            drawRecordingFrame();
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
    if (state == UiState::Recording) {
        recordingStartedAt_ = stateEnteredAt_;
        recordingFrozenElapsedMs_ = 0;
        recordingLastFrameAt_ = 0;
        recordingBarsPhase_ = 0.0f;
        recordingVisualFrozen_ = false;
    } else if (oldState == UiState::Recording && state == UiState::WaitingAck) {
        freezeRecordingVisual();
    } else if (state != UiState::WaitingAck) {
        recordingVisualFrozen_ = false;
    }
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

void UiController::freezeRecordingVisual() {
    if (recordingVisualFrozen_) return;
    const uint32_t now = millis();
    recordingFrozenElapsedMs_ = recordingStartedAt_ ? (uint32_t)(now - recordingStartedAt_) : 0;
    recordingVisualFrozen_ = true;
    dirty_ = true;
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

bool UiController::loadCharacterAssets() {
    if (!LittleFS.begin(false)) {
        Serial.println("[ASSET] LittleFS mount failed");
        return false;
    }

    Serial.printf("[ASSET] LittleFS mounted: total=%lu used=%lu\n",
                  (unsigned long)LittleFS.totalBytes(),
                  (unsigned long)LittleFS.usedBytes());
    bool allReady = true;
    for (uint8_t index = 0; index < tierIndex(EnergyTier::Count); ++index) {
        const EnergyTierStyle &style = ENERGY_STYLES[index];
        characterCanvases_[index] = new M5Canvas(&M5.Display);
        M5Canvas *canvas = characterCanvases_[index];
        canvas->setColorDepth(16);
        canvas->setPsram(true);
        if (!LittleFS.exists(style.assetPath) ||
            !canvas->createSprite(CHARACTER_CANVAS_SIZE, CHARACTER_CANVAS_SIZE)) {
            Serial.printf("[ASSET] unavailable: %s\n", style.assetPath);
            allReady = false;
            continue;
        }
        const uint16_t background = canvas->color565(245, 245, 243);
        canvas->fillScreen(background);
        const int32_t pngX = (CHARACTER_CANVAS_SIZE - style.assetWidth) / 2;
        const int32_t pngY = (CHARACTER_CANVAS_SIZE - style.assetHeight) / 2;
        characterAssetsReady_[index] = canvas->drawPngFile(LittleFS, style.assetPath, pngX, pngY);
        if (!characterAssetsReady_[index]) {
            Serial.printf("[ASSET] PNG decode failed: %s\n", style.assetPath);
            allReady = false;
        }
    }
    errorCanvas_.setColorDepth(16);
    errorCanvas_.setPsram(true);
    if (LittleFS.exists(ERROR_ASSET_PATH) &&
        errorCanvas_.createSprite(ERROR_CANVAS_WIDTH, ERROR_CANVAS_HEIGHT)) {
        const uint16_t errorBackground = errorCanvas_.color565(250, 250, 249);
        errorCanvas_.fillScreen(errorBackground);
        errorAssetReady_ = errorCanvas_.drawPngFile(
            LittleFS,
            ERROR_ASSET_PATH,
            (ERROR_CANVAS_WIDTH - ERROR_ASSET_WIDTH) / 2,
            (ERROR_CANVAS_HEIGHT - ERROR_ASSET_HEIGHT) / 2);
    }
    if (!errorAssetReady_) {
        Serial.printf("[ASSET] unavailable: %s\n", ERROR_ASSET_PATH);
        allReady = false;
    }
    Serial.printf("[ASSET] energy mascots ready=%d\n", allReady);
    return allReady;
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

bool UiController::ensureRecordingCanvas() {
    if (recordingCanvasReady_ &&
        recordingCanvas_.width() == M5.Display.width() &&
        recordingCanvas_.height() == M5.Display.height()) {
        return true;
    }

    recordingCanvas_.deleteSprite();
    recordingCanvas_.setColorDepth(16);
    recordingCanvas_.setPsram(true);
    recordingCanvasReady_ = recordingCanvas_.createSprite(M5.Display.width(), M5.Display.height());
    if (!recordingCanvasReady_) {
        Serial.println("[UI] recording canvas allocation failed");
    }
    return recordingCanvasReady_;
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

    const EnergyTierStyle &style = styleFor(energyTier_);
    const uint16_t backgroundColor = standbyCanvas_.color565(10, 12, 9);
    const uint16_t frontColor = standbyCanvas_.color565(style.frontR, style.frontG, style.frontB);
    const uint16_t middleColor = standbyCanvas_.color565(style.middleR, style.middleG, style.middleB);
    const uint16_t backColor = standbyCanvas_.color565(style.backR, style.backG, style.backB);
    const float surfaceY = standbyCanvas_.height() * (1.0f - style.fillPercent / 100.0f);

    standbyCanvas_.fillScreen(backgroundColor);
    const float originalBaseY = standbyCanvas_.height() * 0.46f;
    const float tierOffset = surfaceY - originalBaseY;
    drawWaveLayer(backColor, standbyBackPhase_, STANDBY_BACK_AMPLITUDE, STANDBY_BACK_WAVELENGTH, tierOffset + 10.0f);
    drawWaveLayer(middleColor, standbyMiddlePhase_, STANDBY_MIDDLE_AMPLITUDE, STANDBY_MIDDLE_WAVELENGTH, tierOffset + 5.0f);
    drawWaveLayer(frontColor, standbyFrontPhase_, STANDBY_FRONT_AMPLITUDE, STANDBY_FRONT_WAVELENGTH, tierOffset);
    standbyCanvas_.pushSprite(0, 0);

    standbyFrontPhase_ += STANDBY_FRONT_PHASE_STEP;
    standbyMiddlePhase_ += STANDBY_MIDDLE_PHASE_STEP;
    standbyBackPhase_ += STANDBY_BACK_PHASE_STEP;
    standbyLastFrameAt_ = millis();
}

void UiController::drawRecordingBars(int32_t centerX, int32_t baselineY, float phase) {
    static constexpr int32_t barCount = 10;
    static constexpr int32_t barWidth = 8;
    static constexpr int32_t barGap = 10;
    const int32_t totalWidth = barCount * barWidth + (barCount - 1) * barGap;
    const int32_t startX = centerX - totalWidth / 2;
    const uint16_t barColor = recordingCanvas_.color565(245, 244, 238);

    for (int32_t i = 0; i < barCount; ++i) {
        const float slow = sinf(phase + i * 0.74f);
        const float fast = sinf(phase * 1.63f + i * 1.11f);
        const int32_t height = 22 + (int32_t)((slow * 0.5f + 0.5f) * 34.0f) +
                               (int32_t)((fast * 0.5f + 0.5f) * 16.0f);
        const int32_t x = startX + i * (barWidth + barGap);
        recordingCanvas_.fillRoundRect(x, baselineY - height, barWidth, height, barWidth / 2, barColor);
    }
}

void UiController::drawRecordingFrame() {
    if (!ensureRecordingCanvas()) {
        M5.Display.fillScreen(TFT_BLACK);
        return;
    }

    const int32_t width = recordingCanvas_.width();
    const int32_t height = recordingCanvas_.height();
    const int32_t centerX = width / 2;
    const uint16_t backgroundColor = recordingCanvas_.color565(12, 12, 10);
    const uint16_t whiteColor = recordingCanvas_.color565(245, 244, 238);
    const uint16_t mutedColor = recordingCanvas_.color565(145, 145, 138);
    const uint16_t greenColor = recordingCanvas_.color565(98, 201, 0);

    const uint32_t elapsedMs = recordingVisualFrozen_
        ? recordingFrozenElapsedMs_
        : (recordingStartedAt_ ? (uint32_t)(millis() - recordingStartedAt_) : 0);
    const uint32_t elapsedSeconds = elapsedMs / 1000;
    char timerText[8];
    snprintf(timerText, sizeof(timerText), "%02lu:%02lu",
             (unsigned long)(elapsedSeconds / 60),
             (unsigned long)(elapsedSeconds % 60));

    recordingCanvas_.fillScreen(backgroundColor);
    recordingCanvas_.fillCircle(centerX - 56, 88, 8, greenColor);

    recordingCanvas_.setTextDatum(middle_left);
    recordingCanvas_.setTextColor(mutedColor, backgroundColor);
    recordingCanvas_.setFont(&fonts::Font2);
    recordingCanvas_.setTextSize(1);
    recordingCanvas_.drawString("RECORDING", centerX - 32, 88);

    recordingCanvas_.setTextDatum(middle_center);
    recordingCanvas_.setTextColor(whiteColor, backgroundColor);
    recordingCanvas_.setFont(&fonts::DejaVu72);
    recordingCanvas_.setTextSize(1);
    recordingCanvas_.drawString(timerText, centerX, 155);

    drawRecordingBars(centerX, 284, recordingBarsPhase_);

    recordingCanvas_.setTextColor(mutedColor, backgroundColor);
    recordingCanvas_.setFont(&fonts::efontCN_16_b);
    recordingCanvas_.setTextSize(1);
    recordingCanvas_.drawString("按黄色按键.保存", centerX, height - 86);

    recordingCanvas_.pushSprite(0, 0);
    recordingLastFrameAt_ = millis();
}

void UiController::drawSavedFrame() {
    const int32_t width = M5.Display.width();
    const int32_t height = M5.Display.height();
    const int32_t centerX = width / 2;
    const uint16_t backgroundColor = M5.Display.color565(243, 243, 241);
    const uint16_t greenColor = M5.Display.color565(98, 201, 0);
    const uint16_t blackColor = M5.Display.color565(18, 18, 16);
    const uint16_t mutedColor = M5.Display.color565(178, 176, 168);

    M5.Display.startWrite();
    M5.Display.fillScreen(backgroundColor);

    const int32_t checkCenterY = 112;
    M5.Display.fillCircle(centerX, checkCenterY, 37, greenColor);
    M5.Display.drawLine(centerX - 17, checkCenterY - 1, centerX - 4, checkCenterY + 12, blackColor);
    M5.Display.drawLine(centerX - 4, checkCenterY + 12, centerX + 18, checkCenterY - 15, blackColor);
    M5.Display.drawLine(centerX - 16, checkCenterY, centerX - 4, checkCenterY + 12, blackColor);
    M5.Display.drawLine(centerX - 3, checkCenterY + 12, centerX + 19, checkCenterY - 14, blackColor);

    M5.Display.setTextDatum(middle_center);
    M5.Display.setTextColor(mutedColor, backgroundColor);
    M5.Display.setFont(&fonts::Font2);
    M5.Display.setTextSize(1);
    M5.Display.drawString("SAVED", centerX, 172);

    M5.Display.setTextColor(blackColor, backgroundColor);
    M5.Display.setFont(&fonts::efontCN_24_b);
    M5.Display.setTextSize(3);
    M5.Display.drawString("已记录", centerX, 246);

    M5.Display.setTextColor(mutedColor, backgroundColor);
    M5.Display.setFont(&fonts::efontCN_24_b);
    M5.Display.setTextSize(1);
    M5.Display.drawString("稍后会在App中完成理解", centerX, 318);

    M5.Display.endWrite();
}

void UiController::drawErrorFrame() {
    const int32_t width = M5.Display.width();
    const int32_t height = M5.Display.height();
    const int32_t centerX = width / 2;
    const int32_t centerY = height / 2;
    const int32_t circleRadius = (width < height ? width : height) / 2 - 23;
    const uint16_t pageBackground = M5.Display.color565(232, 232, 229);
    const uint16_t circleBackground = M5.Display.color565(250, 250, 249);
    const uint16_t ink = M5.Display.color565(22, 21, 17);

    M5.Display.startWrite();
    M5.Display.fillScreen(pageBackground);
    M5.Display.fillCircle(centerX, centerY, circleRadius, circleBackground);

    if (errorAssetReady_) {
        errorCanvas_.pushSprite(centerX - ERROR_CANVAS_WIDTH / 2, 63);
    }

    M5.Display.setTextDatum(middle_center);
    M5.Display.setTextWrap(false);
    M5.Display.setTextColor(ink, circleBackground);
    M5.Display.setFont(&fonts::efontCN_24_b);
    M5.Display.setTextSize(1);
    M5.Display.drawString("我先休息一下", centerX, 296);
    M5.Display.drawString("马上回来～", centerX, 348);
    M5.Display.endWrite();
}

void UiController::drawWakeTicks(int32_t centerX, int32_t centerY, int32_t radius, uint16_t color) {
    for (int32_t index = 0; index < 24; ++index) {
        const float angle = index * WAVE_TWO_PI / 24.0f - WAVE_TWO_PI / 4.0f;
        const int32_t innerRadius = radius - (index % 4 == 0 ? 23 : 13);
        const int32_t x1 = centerX + (int32_t)roundf(cosf(angle) * innerRadius);
        const int32_t y1 = centerY + (int32_t)roundf(sinf(angle) * innerRadius);
        const int32_t x2 = centerX + (int32_t)roundf(cosf(angle) * radius);
        const int32_t y2 = centerY + (int32_t)roundf(sinf(angle) * radius);
        M5.Display.drawLine(x1, y1, x2, y2, color);
        if (index % 4 == 0) M5.Display.drawLine(x1 + 1, y1, x2 + 1, y2, color);
    }
}

void UiController::drawWakeNeedle(int32_t centerX, int32_t centerY, int32_t radius, int16_t degrees) {
    const float angle = degrees * WAVE_TWO_PI / 360.0f - WAVE_TWO_PI / 4.0f;
    const int32_t innerRadius = radius - 34;
    const int32_t outerRadius = radius - 6;
    const int32_t x1 = centerX + (int32_t)roundf(cosf(angle) * innerRadius);
    const int32_t y1 = centerY + (int32_t)roundf(sinf(angle) * innerRadius);
    const int32_t x2 = centerX + (int32_t)roundf(cosf(angle) * outerRadius);
    const int32_t y2 = centerY + (int32_t)roundf(sinf(angle) * outerRadius);
    const int32_t dotX = centerX + (int32_t)roundf(cosf(angle) * (radius - 20));
    const int32_t dotY = centerY + (int32_t)roundf(sinf(angle) * (radius - 20));
    const uint16_t ink = M5.Display.color565(22, 21, 17);
    const uint16_t green = M5.Display.color565(104, 195, 0);
    M5.Display.drawLine(x1, y1, x2, y2, ink);
    M5.Display.drawLine(x1 + 1, y1, x2 + 1, y2, ink);
    M5.Display.fillCircle(dotX, dotY, 6, green);
    M5.Display.drawCircle(dotX, dotY, 6, ink);
}

void UiController::drawCharacterFrame() {
    const EnergyTierStyle &style = styleFor(energyTier_);
    const int32_t width = M5.Display.width();
    const int32_t height = M5.Display.height();
    const int32_t centerX = width / 2;
    const int32_t centerY = height / 2;
    const int32_t radius = (width < height ? width : height) / 2 - 27;
    const uint16_t background = M5.Display.color565(245, 245, 243);
    const uint16_t ink = M5.Display.color565(22, 21, 17);
    const uint16_t muted = M5.Display.color565(181, 181, 174);
    const uint16_t ticks = M5.Display.color565(213, 212, 205);

    M5.Display.startWrite();
    M5.Display.fillScreen(background);
    drawWakeTicks(centerX, centerY, radius, ticks);
    drawWakeNeedle(centerX, centerY, radius, style.needleDegrees);

    const uint8_t index = tierIndex(energyTier_);
    if (characterAssetsReady_[index] && characterCanvases_[index]) {
        characterCanvases_[index]->pushSprite(centerX - CHARACTER_CANVAS_SIZE / 2, 62);
    }

    M5.Display.setTextDatum(middle_center);
    M5.Display.setTextWrap(false);
    M5.Display.setTextColor(ink, background);
    M5.Display.setFont(&fonts::efontCN_24_b);
    M5.Display.setTextSize(2);
    M5.Display.drawString(style.label, centerX, 274);

    M5.Display.setTextColor(muted, background);
    M5.Display.setTextSize(1);
    M5.Display.drawString(style.suggestion, centerX, 324);
    M5.Display.setFont(&fonts::efontCN_16_b);
    M5.Display.drawString("按住顶部按键 · 记录", centerX, height - 58);
    M5.Display.endWrite();
}

void UiController::drawState() {
    const UiState state = state_;
    if (state == UiState::StandbyWave) {
        drawStandbyWave();
        return;
    }
    if (state == UiState::Recording ||
        (state == UiState::WaitingAck && recordingVisualFrozen_)) {
        drawRecordingFrame();
        return;
    }
    if (state == UiState::Saved) {
        drawSavedFrame();
        return;
    }
    if (state == UiState::Error) {
        drawErrorFrame();
        return;
    }
    if (state == UiState::Character) {
        drawCharacterFrame();
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
