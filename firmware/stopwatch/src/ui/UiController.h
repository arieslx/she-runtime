#pragma once

#include <M5Unified.h>
#include "EnergyTier.h"
#include "UiState.h"

class UiController {
public:
    UiController();
    void begin();
    void update();

    void setState(UiState state);
    void setBleState(UiBleState state);
    void setLastInput(const char *input);
    void setProgress(uint16_t sentFrames, uint16_t totalFrames);
    void setError(const char *errorCode);
    void freezeRecordingVisual();
    void cycleEnergyTier();

    UiState state() const { return state_; }
    EnergyTier energyTier() const { return energyTier_; }

private:
    bool loadCharacterAssets();
    bool ensureStandbyCanvas();
    bool ensureRecordingCanvas();
    void drawStandbyWave();
    void drawWaveLayer(uint16_t color, float phase, float amplitude, float wavelength, float baseYOffset);
    void drawRecordingFrame();
    void drawRecordingBars(int32_t centerX, int32_t baselineY, float phase);
    void drawSavedFrame();
    void drawErrorFrame();
    void drawCharacterFrame();
    void drawWakeTicks(int32_t centerX, int32_t centerY, int32_t radius, uint16_t color);
    void drawWakeNeedle(int32_t centerX, int32_t centerY, int32_t radius, int16_t degrees);
    void drawState();
    static const char *stateText(UiState state);
    static const char *stateLogText(UiState state);
    static uint32_t stateDuration(UiState state);
    static uint32_t backgroundColor(UiState state);
    static uint32_t textColor(UiState state);

    volatile UiState state_ = UiState::StandbyWave;
    volatile UiBleState bleState_ = UiBleState::Booting;
    const char *volatile lastInput_ = "NONE";
    const char *volatile lastError_ = "NONE";
    volatile uint16_t sentFrames_ = 0;
    volatile uint16_t totalFrames_ = 500;
    volatile bool dirty_ = true;
    volatile uint32_t stateEnteredAt_ = 0;
    M5Canvas standbyCanvas_;
    M5Canvas recordingCanvas_;
    M5Canvas errorCanvas_;
    M5Canvas *characterCanvases_[static_cast<uint8_t>(EnergyTier::Count)] = {};
    bool standbyCanvasReady_ = false;
    bool recordingCanvasReady_ = false;
    bool errorAssetReady_ = false;
    bool characterAssetsReady_[static_cast<uint8_t>(EnergyTier::Count)] = {};
    EnergyTier energyTier_ = EnergyTier::Steady;
    uint32_t standbyLastFrameAt_ = 0;
    float standbyFrontPhase_ = 0.0f;
    float standbyMiddlePhase_ = 0.0f;
    float standbyBackPhase_ = 0.0f;
    uint32_t recordingStartedAt_ = 0;
    uint32_t recordingFrozenElapsedMs_ = 0;
    uint32_t recordingLastFrameAt_ = 0;
    float recordingBarsPhase_ = 0.0f;
    bool recordingVisualFrozen_ = false;
};
