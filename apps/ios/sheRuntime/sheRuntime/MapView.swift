import SwiftUI

@MainActor
struct MapView: View {
    @StateObject private var viewModel: EnergyMapViewModel

    init() {
        _viewModel = StateObject(wrappedValue: EnergyMapViewModel())
    }

    init(viewModel: EnergyMapViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(C.t("map.eyebrow"))
                    .font(.system(size: 11, weight: .bold)).tracking(2.4)
                    .foregroundStyle(AppPalette.faint)
                Text(C.t("map.titleNative"))
                    .font(.system(size: 38, weight: .bold, design: .serif))
                    .foregroundStyle(AppPalette.ink).padding(.top, 5)
                Text(rangeTitle)
                    .font(.system(size: 14)).foregroundStyle(AppPalette.muted).padding(.top, 5)
                dayPicker.padding(.top, 16)
                content.padding(.top, 14)
                Spacer(minLength: 120)
            }
            .padding(.horizontal, 16).padding(.top, 18)
        }
        .background(AppPalette.background)
        .task { await viewModel.load() }
    }

    private var rangeTitle: String {
        "08:00 — 20:00 · \(viewModel.isSelectedToday ? C.t("map.dayToday") : shortDate(viewModel.selectedDate))"
    }

    private var dayPicker: some View {
        HStack(spacing: 10) {
            ForEach(viewModel.selectableDates, id: \.self) { date in
                let selected = Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate)
                Button { viewModel.select(date: date) } label: {
                    Text(Calendar.current.isDateInToday(date) ? C.t("map.dayToday") : shortDate(date))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selected ? .white : AppPalette.muted)
                        .frame(width: 62, height: 40)
                        .background(selected ? AppPalette.ink : .white)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(selected ? 0 : 0.035), radius: 10, y: 5)
                }.buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            statusCard(title: C.t("map.loading"), body: C.t("map.loadingBody"), progress: true)
        case .noPermission(let message):
            statusCard(title: C.t("map.noPermission"), body: message, action: C.t("map.retry")) {
                Task { await viewModel.retry() }
            }
        case .noData:
            statusCard(title: C.t("map.noData"), body: C.t("map.noDataBody"))
        case .buildingBaseline(let days, let samples):
            statusCard(
                title: C.t("map.baselineBuilding"),
                body: String(format: C.t("map.baselineProgress"), days, samples)
            )
        case .loaded(let result):
            VStack(spacing: 14) {
                chartCard(result)
                windowCards(result)
                methodologyCard
            }
        }
    }

    private func chartCard(_ result: EnergyMapResult) -> some View {
        VStack(spacing: 0) {
            EnergyMapChart(result: result, selectedDate: viewModel.selectedDate, showsCurrent: viewModel.isSelectedToday)
                .frame(height: 235)
            Text(result.hasEstimatedTrend ? C.t("map.trendNote") : C.t("map.trendNeedsHistory"))
                .font(.system(size: 12)).foregroundStyle(AppPalette.faint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22).padding(.bottom, 20)
        }
        .background(.white).clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    @ViewBuilder private func windowCards(_ result: EnergyMapResult) -> some View {
        if let best = result.bestFocusWindow, let low = result.lowWindow {
            HStack(alignment: .top, spacing: 10) {
                insightCard(
                    eyebrow: C.t("map.bestFocus"), range: timeRange(best),
                    note: C.t("map.bestRelativeNote"),
                    color: Color(red: 176 / 255, green: 218 / 255, blue: 132 / 255)
                )
                insightCard(
                    eyebrow: C.t("map.lowWindow"), range: timeRange(low),
                    note: C.t("map.lowRelativeNote"), color: AppPalette.blue
                )
            }
        } else {
            let body = result.historicalDayCount < 7 ? C.t("map.windowNeedsHistory") : C.t("map.noClearWindow")
            statusCard(title: C.t("map.exploratoryWindows"), body: body)
        }
    }

    private var methodologyCard: some View {
        Text(C.t("map.relativeBaselineNote"))
            .font(.system(size: 12)).foregroundStyle(AppPalette.muted).lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(.white).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func insightCard(eyebrow: String, range: String, note: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow).font(.system(size: 10, weight: .bold)).tracking(1.2)
                .foregroundStyle(AppPalette.muted).padding(.horizontal, 11)
                .frame(height: 28).background(color.opacity(0.82)).clipShape(Capsule())
            Text(range).font(.system(size: 19, weight: .bold, design: .serif)).foregroundStyle(AppPalette.ink)
            Text(note).font(.system(size: 12)).foregroundStyle(AppPalette.muted)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .padding(16).background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func statusCard(
        title: String,
        body: String,
        progress: Bool = false,
        action: String? = nil,
        handler: @escaping () -> Void = {}
    ) -> some View {
        VStack(spacing: 14) {
            if progress { ProgressView().tint(AppPalette.green) }
            Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(AppPalette.ink)
            Text(body).font(.system(size: 14)).foregroundStyle(AppPalette.muted)
                .multilineTextAlignment(.center).lineSpacing(4)
            if let action {
                Button(action, action: handler).buttonStyle(.borderedProminent).tint(AppPalette.green)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220).padding(24)
        .background(.white).clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.defaultDigits).day(.twoDigits).locale(Locale.current))
    }

    private func timeRange(_ interval: DateInterval) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: interval.start))–\(formatter.string(from: interval.end))"
    }
}

private struct EnergyMapChart: View {
    let result: EnergyMapResult
    let selectedDate: Date
    let showsCurrent: Bool
    private let labels = ["08", "10", "12", "14", "16", "18", "20"]

    var body: some View {
        GeometryReader { proxy in
            let plot = CGRect(x: 29, y: 35, width: proxy.size.width - 57, height: 135)
            ZStack {
                RadialGradient(colors: [AppPalette.green.opacity(0.20), AppPalette.green.opacity(0)],
                               center: .topTrailing, startRadius: 5, endRadius: 135)
                observedPaths(in: plot).stroke(AppPalette.ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                estimatedPath(in: plot).stroke(AppPalette.faint.opacity(0.9),
                    style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [2, 7]))
                currentMarker(in: plot)
                hourLabels
            }
        }
    }

    private func observedPaths(in plot: CGRect) -> Path {
        let points = result.points.filter { $0.kind == .observed }.sorted { $0.date < $1.date }
        return Path { path in
            var previous: EnergyMapPoint?
            for point in points {
                let position = position(for: point, in: plot)
                if let previous, point.date.timeIntervalSince(previous.date) <= 31 * 60 {
                    path.addLine(to: position)
                } else {
                    path.move(to: position)
                }
                previous = point
            }
        }
    }

    private func estimatedPath(in plot: CGRect) -> Path {
        let observed = result.points.filter { $0.kind == .observed }.max(by: { $0.date < $1.date })
        let estimates = result.points.filter { $0.kind == .estimated }.sorted { $0.date < $1.date }
        return Path { path in
            if let observed { path.move(to: position(for: observed, in: plot)) }
            for point in estimates { path.addLine(to: position(for: point, in: plot)) }
        }
    }

    @ViewBuilder private func currentMarker(in plot: CGRect) -> some View {
        if showsCurrent, let score = result.currentScore, let date = result.latestSampleDate {
            let hours = result.freshness > 0 ? -4 * log(result.freshness) : .infinity
            let point = CGPoint(x: xPosition(date, in: plot), y: yPosition(score, in: plot))
            Circle().fill(AppPalette.green.opacity(max(0.35, result.freshness)))
                .frame(width: 10, height: 10).overlay(Circle().stroke(.white, lineWidth: 2)).position(point)
            Text(currentLabel(hours: hours))
                .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 13).frame(height: 31)
                .background(AppPalette.green.opacity(max(0.55, result.freshness))).clipShape(Capsule())
                .position(x: min(plot.maxX - 45, max(plot.minX + 45, point.x)), y: max(20, point.y - 32))
        }
    }

    private var hourLabels: some View {
        HStack {
            ForEach(labels, id: \.self) { label in
                Text(label).font(.system(size: 10)).foregroundStyle(AppPalette.faint)
                if label != labels.last { Spacer() }
            }
        }
        .padding(.horizontal, 27).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 20)
    }

    private func position(for point: EnergyMapPoint, in plot: CGRect) -> CGPoint {
        CGPoint(x: xPosition(point.date, in: plot), y: yPosition(point.score, in: plot))
    }

    private func xPosition(_ date: Date, in plot: CGRect) -> CGFloat {
        let start = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: selectedDate)!
        let ratio = min(1, max(0, date.timeIntervalSince(start) / (12 * 3600)))
        return plot.minX + plot.width * ratio
    }

    private func yPosition(_ score: Double, in plot: CGRect) -> CGFloat {
        plot.maxY - plot.height * CGFloat((score - 5) / 90)
    }

    private func currentLabel(hours: Double) -> String {
        guard hours <= 6 else { return C.t("map.waitingForData") }
        let state: String
        switch result.currentState {
        case .high: state = C.t("map.stateHigh")
        case .normal: state = C.t("map.stateNormal")
        case .low: state = C.t("map.stateLow")
        case .insufficientData: return C.t("map.waitingForData")
        }
        return hours <= 2 ? "\(state) · \(C.t("map.now"))" : String(format: C.t("map.latestStatus"), state)
    }
}
