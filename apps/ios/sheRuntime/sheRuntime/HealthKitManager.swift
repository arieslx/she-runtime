//
//  HealthKitManager.swift
//  sheRuntime
//
//  Created by ari on 2026/8/27.
//

import Foundation
import HealthKit
import Combine

@MainActor
final class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()

    @Published var stepCount: Int = 0
    @Published var statusMessage = "尚未连接 Apple Health"

    func requestAuthorizationAndLoadSteps() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            statusMessage = "当前设备不支持 Apple Health"
            return
        }

        guard let stepType = HKQuantityType.quantityType(
            forIdentifier: .stepCount
        ) else {
            statusMessage = "无法创建步数数据类型"
            return
        }

        do {
            try await healthStore.requestAuthorization(
                toShare: [],
                read: [stepType]
            )

            await loadTodaySteps(stepType: stepType)
        } catch {
            statusMessage = "授权失败：\(error.localizedDescription)"
        }
    }

    private func loadTodaySteps(stepType: HKQuantityType) async {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: Date(),
            options: .strictStartDate
        )

        do {
            let result = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Double, Error>) in

                let query = HKStatisticsQuery(
                    quantityType: stepType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum
                ) { _, statistics, error in
                    if let error {
                        let nsError = error as NSError

                        if nsError.domain == HKErrorDomain,
                           nsError.code == HKError.errorNoData.rawValue {
                            continuation.resume(returning: 0)
                        } else {
                            continuation.resume(throwing: error)
                        }

                        return
                    }

                    let steps = statistics?
                        .sumQuantity()?
                        .doubleValue(for: .count()) ?? 0

                    continuation.resume(returning: steps)
                }

                healthStore.execute(query)
            }

            stepCount = Int(result)
            statusMessage = "Apple Health 已连接"
        } catch {
            statusMessage = "读取步数失败：\(error.localizedDescription)"
        }
    }
}
