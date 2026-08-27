#include "UiController.h"

#include <cstring>

void UiController::begin() {
    M5.Display.setBrightness(96);
    M5.Display.setRotation(0);
    dirty_ = true;
    update();
}

void UiController::update() {
    if (!dirty_ || M5.Display.width() <= 0) return;
    dirty_ = false;
    drawPlaceholder();
}

void UiController::setState(UiState state) {
    state_ = state;
    dirty_ = true;
}

void UiController::setBleState(UiBleState state) {
    bleState_ = state;
    dirty_ = true;
}

void UiController::setLastInput(const char *input) {
    lastInput_ = input;
    dirty_ = true;
}

void UiController::setProgress(uint16_t sentFrames, uint16_t totalFrames) {
    sentFrames_ = sentFrames;
    totalFrames_ = totalFrames;
    dirty_ = true;
}

void UiController::setError(const char *errorCode) {
    lastError_ = errorCode;
    state_ = UiState::Error;
    dirty_ = true;
}

const char *UiController::stateText(UiState state) {
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

const char *UiController::bleText(UiBleState state) {
    switch (state) {
    case UiBleState::Booting: return "BOOTING";
    case UiBleState::Advertising: return "ADVERTISING";
    case UiBleState::Connected: return "CONNECTED";
    case UiBleState::Ready: return "READY";
    }
    return "UNKNOWN";
}

void UiController::drawPlaceholder() {
    M5.Display.startWrite();
    M5.Display.fillScreen(TFT_BLACK);
    M5.Display.setTextDatum(top_left);
    M5.Display.setTextWrap(false);
    M5.Display.setTextSize(2);
    M5.Display.setTextColor(TFT_WHITE, TFT_BLACK);
    M5.Display.setCursor(18, 20); M5.Display.print("sheRuntime Probe");
    M5.Display.drawFastHLine(18, 48, M5.Display.width() - 36, TFT_DARKGREY);
    M5.Display.setCursor(18, 70); M5.Display.printf("BLE:    %s", bleText(bleState_));
    uint32_t stateColor = state_ == UiState::Saved ? TFT_GREEN
                        : state_ == UiState::Error ? TFT_RED : TFT_WHITE;
    M5.Display.setTextColor(stateColor, TFT_BLACK);
    M5.Display.setCursor(18, 105); M5.Display.printf("UI:     %s", stateText(state_));
    M5.Display.setTextColor(TFT_WHITE, TFT_BLACK);
    M5.Display.setCursor(18, 140); M5.Display.printf("INPUT:  %s", lastInput_);
    M5.Display.setCursor(18, 175); M5.Display.printf("FRAMES: %u / %u", sentFrames_, totalFrames_);
    M5.Display.setTextColor(std::strcmp(lastError_, "NONE") == 0 ? TFT_LIGHTGREY : TFT_ORANGE, TFT_BLACK);
    M5.Display.setCursor(18, 210); M5.Display.printf("LASTERR:%s", lastError_);
    M5.Display.endWrite();
}
