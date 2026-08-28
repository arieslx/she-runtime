// HealthDataAuthService.swift — 工人A(数据层)
// 申请 Apple Health 全部可读数据类型的读权限。
// 独立持有自己的 HKHealthStore，不触碰 HealthKitManager。
// 纯服务层：无任何用户可见文案。

import Foundation
import HealthKit

final class HealthDataAuthService: @unchecked Sendable {
    static let shared = HealthDataAuthService()

    enum AuthError: Error {
        case healthDataUnavailable
    }

    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    /// 申请所有可枚举的 HealthKit 读权限（quantity + category + workout + characteristic）。
    /// 不存在"一键全类型"API，此处手工列全；宁多勿少，创建失败的类型静默跳过。
    func requestFullAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw AuthError.healthDataUnavailable
        }
        try await healthStore.requestAuthorization(toShare: [], read: Self.allReadTypes())
    }

    // MARK: - 类型枚举

    static func allReadTypes() -> Set<HKObjectType> {
        var types = Set<HKObjectType>()

        for identifier in quantityIdentifiers() {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        for identifier in categoryIdentifiers() {
            if let type = HKCategoryType.categoryType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        for identifier in characteristicIdentifiers() {
            if let type = HKCharacteristicType.characteristicType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        types.insert(HKObjectType.workoutType())
        types.insert(HKSeriesType.heartbeat())
        types.insert(HKSeriesType.workoutRoute())
        types.insert(HKObjectType.activitySummaryType())
        if let audiogram = HKObjectType.audiogramSampleType() as HKObjectType? {
            types.insert(audiogram)
        }
        types.insert(HKObjectType.electrocardiogramType())
        return types
    }

    private static func quantityIdentifiers() -> [HKQuantityTypeIdentifier] {
        var ids: [HKQuantityTypeIdentifier] = [
            // 心血管
            .heartRate,
            .restingHeartRate,
            .walkingHeartRateAverage,
            .heartRateVariabilitySDNN,
            .heartRateRecoveryOneMinute,
            .atrialFibrillationBurden,
            .peripheralPerfusionIndex,
            .bloodPressureSystolic,
            .bloodPressureDiastolic,
            .oxygenSaturation,
            .vo2Max,
            // 呼吸
            .respiratoryRate,
            .forcedExpiratoryVolume1,
            .forcedVitalCapacity,
            .peakExpiratoryFlowRate,
            .inhalerUsage,
            // 体温
            .bodyTemperature,
            .basalBodyTemperature,
            .appleSleepingWristTemperature,
            // 身体测量
            .bodyMass,
            .bodyMassIndex,
            .bodyFatPercentage,
            .leanBodyMass,
            .height,
            .waistCircumference,
            // 活动
            .stepCount,
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
            .distanceWheelchair,
            .distanceDownhillSnowSports,
            .flightsClimbed,
            .pushCount,
            .swimmingStrokeCount,
            .activeEnergyBurned,
            .basalEnergyBurned,
            .appleExerciseTime,
            .appleStandTime,
            .appleMoveTime,
            .nikeFuel,
            // 步态 / 移动性
            .walkingSpeed,
            .walkingStepLength,
            .walkingDoubleSupportPercentage,
            .walkingAsymmetryPercentage,
            .sixMinuteWalkTestDistance,
            .stairAscentSpeed,
            .stairDescentSpeed,
            .appleWalkingSteadiness,
            .runningSpeed,
            .runningPower,
            .runningStrideLength,
            .runningGroundContactTime,
            .runningVerticalOscillation,
            .cyclingSpeed,
            .cyclingPower,
            .cyclingCadence,
            .cyclingFunctionalThresholdPower,
            // 听力 / 环境
            .environmentalAudioExposure,
            .headphoneAudioExposure,
            .environmentalSoundReduction,
            .uvExposure,
            // 营养
            .dietaryEnergyConsumed,
            .dietaryCarbohydrates,
            .dietaryProtein,
            .dietaryFatTotal,
            .dietaryFatSaturated,
            .dietaryFatMonounsaturated,
            .dietaryFatPolyunsaturated,
            .dietaryCholesterol,
            .dietarySugar,
            .dietaryFiber,
            .dietarySodium,
            .dietaryPotassium,
            .dietaryCalcium,
            .dietaryIron,
            .dietaryMagnesium,
            .dietaryZinc,
            .dietaryIodine,
            .dietaryVitaminA,
            .dietaryVitaminB6,
            .dietaryVitaminB12,
            .dietaryVitaminC,
            .dietaryVitaminD,
            .dietaryVitaminE,
            .dietaryVitaminK,
            .dietaryThiamin,
            .dietaryRiboflavin,
            .dietaryNiacin,
            .dietaryFolate,
            .dietaryBiotin,
            .dietaryPantothenicAcid,
            .dietaryPhosphorus,
            .dietaryChromium,
            .dietaryCopper,
            .dietaryManganese,
            .dietaryMolybdenum,
            .dietarySelenium,
            .dietaryChloride,
            .dietaryCaffeine,
            .dietaryWater,
            // 血糖 / 代谢
            .bloodGlucose,
            .insulinDelivery,
            .bloodAlcoholContent,
            .numberOfAlcoholicBeverages,
            // 其他
            .numberOfTimesFallen,
            .electrodermalActivity,
            .forcedExpiratoryVolume1,
            .physicalEffort,
            .underwaterDepth,
            .waterTemperature,
        ]
        if #available(iOS 17.0, *) {
            ids.append(contentsOf: [
                .timeInDaylight,
                .cyclingSpeed,
            ])
        }
        if #available(iOS 18.0, *) {
            ids.append(contentsOf: [
                .crossCountrySkiingSpeed,
                .distanceCrossCountrySkiing,
                .distancePaddleSports,
                .distanceRowing,
                .distanceSkatingSports,
                .estimatedWorkoutEffortScore,
                .paddleSportsSpeed,
                .rowingSpeed,
                .workoutEffortScore,
                .appleSleepingBreathingDisturbances,
            ])
        }
        return ids
    }

    private static func categoryIdentifiers() -> [HKCategoryTypeIdentifier] {
        var ids: [HKCategoryTypeIdentifier] = [
            // 睡眠 / 正念
            .sleepAnalysis,
            .mindfulSession,
            // 站立 / 事件
            .appleStandHour,
            .lowCardioFitnessEvent,
            .highHeartRateEvent,
            .lowHeartRateEvent,
            .irregularHeartRhythmEvent,
            .environmentalAudioExposureEvent,
            .headphoneAudioExposureEvent,
            .handwashingEvent,
            .toothbrushingEvent,
            .appleWalkingSteadinessEvent,
            // 月经周期 / 生殖健康
            .menstrualFlow,
            .intermenstrualBleeding,
            .infrequentMenstrualCycles,
            .irregularMenstrualCycles,
            .persistentIntermenstrualBleeding,
            .prolongedMenstrualPeriods,
            .cervicalMucusQuality,
            .ovulationTestResult,
            .sexualActivity,
            .contraceptive,
            .pregnancy,
            .pregnancyTestResult,
            .progesteroneTestResult,
            .lactation,
            // 症状（全列）
            .abdominalCramps,
            .acne,
            .appetiteChanges,
            .bladderIncontinence,
            .bloating,
            .breastPain,
            .chestTightnessOrPain,
            .chills,
            .constipation,
            .coughing,
            .diarrhea,
            .dizziness,
            .drySkin,
            .fainting,
            .fatigue,
            .fever,
            .generalizedBodyAche,
            .hairLoss,
            .headache,
            .heartburn,
            .hotFlashes,
            .lossOfSmell,
            .lossOfTaste,
            .lowerBackPain,
            .memoryLapse,
            .moodChanges,
            .nausea,
            .nightSweats,
            .pelvicPain,
            .rapidPoundingOrFlutteringHeartbeat,
            .runnyNose,
            .shortnessOfBreath,
            .sinusCongestion,
            .skippedHeartbeat,
            .sleepChanges,
            .soreThroat,
            .vaginalDryness,
            .vomiting,
            .wheezing,
        ]
        if #available(iOS 18.0, *) {
            ids.append(contentsOf: [
                .bleedingAfterPregnancy,
                .bleedingDuringPregnancy,
                .sleepApneaEvent,
            ])
        }
        return ids
    }

    private static func characteristicIdentifiers() -> [HKCharacteristicTypeIdentifier] {
        [
            .biologicalSex,
            .bloodType,
            .dateOfBirth,
            .fitzpatrickSkinType,
            .wheelchairUse,
            .activityMoveMode,
        ]
    }
}
