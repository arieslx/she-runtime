#pragma once

#include <M5Unified.h>
#include "UiState.h"

class UiController {
public:
    void begin();
    void update();

    void setState(UiState state);
    void setBleState(UiBleState state);
    void setLastInput(const char *input);
    void setProgress(uint16_t sentFrames, uint16_t totalFrames);
    void setError(const char *errorCode);

    UiState state() const { return state_; }

private:
    void drawPlaceholder();
    static const char *stateText(UiState state);
    static const char *bleText(UiBleState state);

    volatile UiState state_ = UiState::StandbyWave;
    volatile UiBleState bleState_ = UiBleState::Booting;
    const char *volatile lastInput_ = "NONE";
    const char *volatile lastError_ = "NONE";
    volatile uint16_t sentFrames_ = 0;
    volatile uint16_t totalFrames_ = 500;
    volatile bool dirty_ = true;
};
