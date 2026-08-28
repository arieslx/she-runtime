# Spec: HRV Energy Map

## Objective

Use HealthKit HRV SDNN samples to render the second-page Energy Map as a relative-to-personal-baseline trend. The result is exploratory, not medical, and never represents remaining physical energy.

## Tech Stack

- SwiftUI and Swift Concurrency
- HealthKit `heartRateVariabilitySDNN`, normalized to milliseconds
- Swift Testing for the UI-independent calculator

## Commands

- Build: `cd apps/ios/sheRuntime && xcodebuild -project sheRuntime.xcodeproj -scheme sheRuntime -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build CODE_SIGNING_ALLOWED=NO`
- Test: `cd apps/ios/sheRuntime && xcodebuild test -project sheRuntime.xcodeproj -scheme sheRuntime -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO`

## Project Structure

- `sheRuntime/HRVHealthKitService.swift`: authorization and raw HRV query only
- `sheRuntime/EnergyMapModels.swift`: value models and states
- `sheRuntime/EnergyMapCalculator.swift`: deterministic Foundation-only algorithm
- `sheRuntime/EnergyMapViewModel.swift`: loading and selected-date orchestration
- `sheRuntime/MapView.swift`: SwiftUI rendering only
- `sheRuntimeTests/EnergyMapCalculatorTests.swift`: calculator tests

## Code Style

```swift
let result = calculator.calculate(samples: samples, targetDate: selectedDate, now: now)
```

Use immutable value models, dependency injection for calendar/time, async HealthKit calls, and JSON-backed user-facing copy.

## Testing Strategy

Unit-test baseline robustness, score monotonicity/clamping, observed gaps, freshness/current labels, historical leakage, estimate/window sufficiency, and time-zone day boundaries. Build the complete app after tests.

## Boundaries

- Always: exclude invalid HRV values, use only personal prior data for baselines, distinguish observed and estimated points, expose insufficient-data states.
- Ask first: changing HealthKit entitlements, adding dependencies, or changing probe behavior.
- Never: use population HRV thresholds, silently substitute mock data at runtime, join observed gaps over three hours, or describe the score as medical energy/stress.

## Success Criteria

- Baseline uses daily log medians from up to 14 valid days before the target date, requiring 5 days and 10 samples.
- Observed points follow the 30-minute/90-minute Gaussian weighting and gap rules.
- Estimates and exploratory windows meet 7-day/5-day-per-slot requirements and never use future data.
- UI supports loading, unavailable/permission error, empty, baseline-building, and loaded states.
- The requested twelve calculator behaviors are covered by automated tests.

## Assumptions

- Querying 42 days is allowed because the requirement says at least 28 days and historical-day baselines need earlier context.
- HealthKit read denial may be indistinguishable from an authorized store with no HRV data; explicit authorization/query failures map to the permission/error state, while an empty successful query maps to no data.
