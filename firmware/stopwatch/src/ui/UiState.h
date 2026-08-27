#pragma once

#include <stdint.h>

enum class UiState : uint8_t {
    StandbyWave,
    Character,
    Recording,
    WaitingAck,
    Saved,
    Error,
};

enum class UiBleState : uint8_t {
    Booting,
    Advertising,
    Connected,
    Ready,
};
