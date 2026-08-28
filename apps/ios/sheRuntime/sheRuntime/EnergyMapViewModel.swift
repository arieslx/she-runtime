import Combine
import Foundation

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

    private let service: any HRVHealthKitServicing
    private let calculator: EnergyMapCalculator
    private let calendar: Calendar
    private var samples: [HRVSample] = []
    private var now: Date

    convenience init() {
        self.init(
            service: HRVHealthKitService(), calculator: EnergyMapCalculator(),
            calendar: .current, now: Date()
        )
    }

    init(
        service: any HRVHealthKitServicing,
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
        state = .loading
        do {
            try await service.requestReadAuthorization()
            let oldestTarget = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: now))!
            let queryStart = calendar.date(byAdding: .day, value: -42, to: oldestTarget)!
            let queryEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
            samples = try await service.loadSamples(from: queryStart, to: queryEnd)
            guard !samples.isEmpty else { state = .noData; return }
            recalculate()
        } catch {
            state = .noPermission(error.localizedDescription)
        }
    }

    func select(date: Date) {
        selectedDate = calendar.startOfDay(for: date)
        guard !samples.isEmpty else { return }
        recalculate()
    }

    func retry() async {
        samples = []
        state = .idle
        await load()
    }

    private func recalculate() {
        let result = calculator.calculate(samples: samples, targetDate: selectedDate, now: now)
        if result.hasReliableBaseline {
            state = .loaded(result)
        } else {
            state = .buildingBaseline(dayCount: result.baselineDayCount, sampleCount: result.baselineSampleCount)
        }
    }
}
