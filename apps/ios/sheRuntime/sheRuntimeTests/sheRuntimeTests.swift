import Foundation
import Testing
@testable import sheRuntime

struct EnergyMapCalculatorTests {
    private let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }()

    @Test func baselineValueScoresAboutFifty() throws {
        let fixture = makeFixture()
        let baseline = fixture.calculator.makeBaseline(samples: fixture.samples, targetDate: fixture.target)
        let value = try #require(fixture.calculator.score(valueMs: 50, baseline: baseline))
        #expect(abs(value - 50) < 0.01)
    }

    @Test func higherThanBaselineScoresHigher() throws {
        let fixture = makeFixture()
        let baseline = fixture.calculator.makeBaseline(samples: fixture.samples, targetDate: fixture.target)
        #expect(try #require(fixture.calculator.score(valueMs: 70, baseline: baseline)) > 50)
    }

    @Test func lowerThanBaselineScoresLower() throws {
        let fixture = makeFixture()
        let baseline = fixture.calculator.makeBaseline(samples: fixture.samples, targetDate: fixture.target)
        #expect(try #require(fixture.calculator.score(valueMs: 30, baseline: baseline)) < 50)
    }

    @Test func extremeScoresRemainClamped() throws {
        let fixture = makeFixture()
        let baseline = fixture.calculator.makeBaseline(samples: fixture.samples, targetDate: fixture.target)
        #expect(try #require(fixture.calculator.score(valueMs: 5, baseline: baseline)) == 5)
        #expect(try #require(fixture.calculator.score(valueMs: 500, baseline: baseline)) == 95)
    }

    @Test func fewerThanFiveBaselineDaysIsInsufficient() {
        let target = date(2026, 8, 20, 12)
        let samples = (1...4).flatMap { offset in
            [sample(day: 20 - offset, hour: 9, value: 50), sample(day: 20 - offset, hour: 10, value: 51)]
        }
        let result = EnergyMapCalculator(calendar: calendar).calculate(samples: samples, targetDate: target, now: target)
        #expect(!result.hasReliableBaseline)
        #expect(result.currentState == .insufficientData)
    }

    @Test func denseDayDoesNotOverweightOtherDays() throws {
        let target = date(2026, 8, 20, 12)
        var samples = (10...18).flatMap { day in
            [sample(day: day, hour: 9, value: 50), sample(day: day, hour: 10, value: 50)]
        }
        for minute in 0..<60 { samples.append(sample(day: 19, hour: 9, minute: minute, value: 200)) }
        let baseline = EnergyMapCalculator(calendar: calendar).makeBaseline(samples: samples, targetDate: target)
        #expect(exp(try #require(baseline.center)) < 60)
    }

    @Test func observedCurveBreaksAcrossGapOverThreeHours() {
        let fixture = makeFixture(todayValues: [(8, 50), (14, 50)])
        let result = fixture.calculator.calculate(samples: fixture.samples, targetDate: fixture.target, now: fixture.target)
        let points = result.points.filter { $0.kind == .observed }.sorted { $0.date < $1.date }
        #expect(zip(points, points.dropFirst()).contains { $1.date.timeIntervalSince($0.date) > 30 * 60 })
    }

    @Test func sampleOlderThanSixHoursDoesNotProduceCurrentState() {
        let target = date(2026, 8, 20, 18)
        let fixture = makeFixture(target: target, todayValues: [(9, 50)])
        let result = fixture.calculator.calculate(samples: fixture.samples, targetDate: target, now: target)
        #expect(result.currentState == .insufficientData)
        #expect(result.latestSampleDate != nil)
    }

    @Test func fewerThanSevenHistoricalDaysProducesNoEstimate() {
        let fixture = makeFixture(baselineDays: 6, todayValues: [(10, 50)])
        let result = fixture.calculator.calculate(samples: fixture.samples, targetDate: fixture.target, now: fixture.target)
        #expect(!result.hasEstimatedTrend)
        #expect(result.points.allSatisfy { $0.kind == .observed })
    }

    @Test func historicalDateIgnoresFutureSamples() {
        let fixture = makeFixture(todayValues: [(10, 50)])
        let base = fixture.calculator.calculate(samples: fixture.samples, targetDate: fixture.target, now: fixture.target)
        let future = sample(day: 21, hour: 10, value: 500)
        let withFuture = fixture.calculator.calculate(samples: fixture.samples + [future], targetDate: fixture.target, now: fixture.target)
        #expect(base == withFuture)
    }

    @Test func insufficientHistoryProducesNoExploratoryWindows() {
        let fixture = makeFixture(baselineDays: 6, todayValues: [(10, 50)])
        let result = fixture.calculator.calculate(samples: fixture.samples, targetDate: fixture.target, now: fixture.target)
        #expect(result.bestFocusWindow == nil)
        #expect(result.lowWindow == nil)
    }

    @Test func timeZoneDayBoundaryExcludesTargetDayFromBaseline() {
        var shanghai = Calendar(identifier: .gregorian)
        shanghai.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let target = shanghai.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 12))!
        var samples: [HRVSample] = []
        for offset in 1...5 {
            let value = shanghai.date(byAdding: .day, value: -offset, to: target)!
            samples.append(HRVSample(valueMs: 50, startDate: value, endDate: value, sourceName: "Test"))
            samples.append(HRVSample(valueMs: 51, startDate: value.addingTimeInterval(60), endDate: value.addingTimeInterval(60), sourceName: "Test"))
        }
        let targetDay = shanghai.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 0, minute: 30))!
        samples.append(HRVSample(valueMs: 300, startDate: targetDay, endDate: targetDay, sourceName: "Test"))
        let baseline = EnergyMapCalculator(calendar: shanghai).makeBaseline(samples: samples, targetDate: target)
        #expect(baseline.sampleCount == 10)
        #expect(baseline.dayCount == 5)
    }

    private func makeFixture(
        target: Date? = nil,
        baselineDays: Int = 8,
        todayValues: [(Int, Double)] = [(10, 50)]
    ) -> (calculator: EnergyMapCalculator, samples: [HRVSample], target: Date) {
        let target = target ?? date(2026, 8, 20, 12)
        var samples: [HRVSample] = []
        for offset in 1...baselineDays {
            samples.append(sample(day: 20 - offset, hour: 9, value: 50))
            samples.append(sample(day: 20 - offset, hour: 10, value: 50))
        }
        for (hour, value) in todayValues { samples.append(sample(day: 20, hour: hour, value: value)) }
        return (EnergyMapCalculator(calendar: calendar), samples, target)
    }

    private func sample(day: Int, hour: Int, minute: Int = 0, value: Double) -> HRVSample {
        let valueDate = date(2026, 8, day, hour, minute)
        return HRVSample(valueMs: value, startDate: valueDate, endDate: valueDate.addingTimeInterval(60), sourceName: "Test")
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
