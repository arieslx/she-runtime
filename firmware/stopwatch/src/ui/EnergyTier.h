#pragma once

#include <stdint.h>

enum class EnergyTier : uint8_t {
    Low = 0,
    Dipping,
    Steady,
    Good,
    Full,
    Count,
};

struct EnergyTierStyle {
    const char *label;
    const char *suggestion;
    const char *assetPath;
    uint8_t assetWidth;
    uint8_t assetHeight;
    uint8_t fillPercent;
    int16_t needleDegrees;
    uint8_t frontR;
    uint8_t frontG;
    uint8_t frontB;
    uint8_t middleR;
    uint8_t middleG;
    uint8_t middleB;
    uint8_t backR;
    uint8_t backG;
    uint8_t backB;
};
