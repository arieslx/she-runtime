import Combine
import Foundation
import OSLog

protocol EnergyMapHealthServicing: Sendable {
    func requestReadAuthorization() async throws
    func loadEnergyMapHealthData(
        for targetDate: Date, now: Date, calendar: Calendar
    ) async throws -> EnergyMapHealthData
}

extension HealthKitManager: EnergyMapHealthServicing {}

@MainActor
final class EnergyMapViewModel: ObservableObject {
    enum ViewState: Equatable {
        case idle
        case loading
        case noPermission(String)
        case noData
        case buildingBaseline(dayCount: Int, sampleCount: Int)
        case loaded(EnergyMapResult)
    }

    @Published private(set) var state: ViewState = .idle
    @Published private(set) var selectedDate: Date
    @Published private(set) var healthSummary: DailyHealthSummary?
    @Published private(set) var currentEnergyState: EnergyState = .insufficientData
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service: any EnergyMapHealthServicing
    private let calculator: EnergyMapCalculator
    private let calendar: Calendar
    private var now: Date
    private var loadTask: Task<Void, Never>?
    private var authorizationTask: Task<Void, Error>?
    private var requestID = UUID()
    private var hasRequestedAuthorization = false
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "sheRuntime", category: "EnergyMap")

    convenience init() {
        self.init(
            service: HealthKitManager.shared, calculator: EnergyMapCalculator(),
            calendar: .current, now: Date()
        )
    }

    init(
        service: any EnergyMapHealthServicing,
        calculator: EnergyMapCalculator,
        calendar: Calendar,
        now: Date
    ) {
        self.service = service
        self.calculator = calculator
        self.calendar = calendar
        self.now = now
        selectedDate = calendar.startOfDay(for: now)
    }

    var selectableDates: [Date] {
        (0...2).compactMap { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: now)) }
    }

    var isSelectedToday: Bool { calendar.isDate(selectedDate, inSameDayAs: now) }

    func load() async {
        guard state == .idle else { return }
        await reloadSelectedDate()
    }

    func refreshTodayState() async {
        await refreshTodayState(now: now)
    }

    func select(date: Date) {
        selectedDate = calendar.startOfDay(for: date)
        startReload()
    }

    func retry() async {
        state = .idle
        hasRequestedAuthorization = false
        await reloadSelectedDate()
    }

    private func startReload() {
        loadTask?.cancel()
        loadTask = Task { await reloadSelectedDate() }
    }

    private func reloadSelectedDate() async {
        let targetDate = selectedDate
        let currentRequestID = UUID()
        requestID = currentRequestID
        isLoading = true
        errorMessage = nil
        healthSummary = nil
        state = .loading
        do {
            try await ensureAuthorization()
            let data = try await service.loadEnergyMapHealthData(
                for: targetDate, now: now, calendar: calendar
            )
            try Task.checkCancellation()
            guard requestID == currentRequestID,
                  calendar.isDate(selectedDate, inSameDayAs: targetDate) else { return }
            healthSummary = data.summary
            applyMapState(samples: data.hrvSamples, targetDate: targetDate)
            isLoading = false
        } catch is CancellationError {
            return
        } catch {
            guard requestID == currentRequestID else { return }
            logger.error("HealthKit date load failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            state = .noPermission(C.t("map.healthDataUnavailable"))
            isLoading = false
        }
    }

    private func refreshTodayState(now: Date) async {
        do {
            try await ensureAuthorization()
            let targetDate = calendar.startOfDay(for: now)
            let data = try await service.loadEnergyMapHealthData(
                for: targetDate, now: now, calendar: calendar
            )
            try Task.checkCancellation()
            let result = calculator.calculate(samples: data.hrvSamples, targetDate: targetDate, now: now)
            currentEnergyState = result.hasReliableBaseline ? result.currentState : .insufficientData
        } catch is CancellationError {
            return
        } catch {
            currentEnergyState = .insufficientData
        }
    }

    private func ensureAuthorization() async throws {
        if hasRequestedAuthorization { return }
        if let authorizationTask {
            try await authorizationTask.value
            hasRequestedAuthorization = true
            return
        }
        let task = Task { try await service.requestReadAuthorization() }
        authorizationTask = task
        do {
            try await task.value
            hasRequestedAuthorization = true
            authorizationTask = nil
        } catch {
            authorizationTask = nil
            throw error
        }
    }

    private func applyMapState(samples: [HRVSample], targetDate: Date) {
        guard !samples.isEmpty else {
            state = .noData
            if calendar.isDate(targetDate, inSameDayAs: now) { currentEnergyState = .insufficientData }
            return
        }
        let result = calculator.calculate(samples: samples, targetDate: targetDate, now: now)
        if result.hasReliableBaseline {
            state = .loaded(result)
            if calendar.isDate(targetDate, inSameDayAs: now) { currentEnergyState = result.currentState }
        } else {
            state = .buildingBaseline(dayCount: result.baselineDayCount, sampleCount: result.baselineSampleCount)
            if calendar.isDate(targetDate, inSameDayAs: now) { currentEnergyState = .insufficientData }
        }
    }
}
