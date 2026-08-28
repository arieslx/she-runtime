import SwiftUI

struct MapView: View {
    @State private var selectedDay = 0

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Text(C.t("map.eyebrow"))
                    .font(.system(size: 11, weight: .bold)).tracking(2.4)
                    .foregroundStyle(AppPalette.faint)
                Text(C.t("map.titleNative"))
                    .font(.system(size: 38, weight: .bold, design: .serif))
                    .foregroundStyle(AppPalette.ink).padding(.top, 5)
                Text(C.t("map.rangeToday"))
                    .font(.system(size: 14)).foregroundStyle(AppPalette.muted).padding(.top, 5)
                dayPicker.padding(.top, 16)
                chartCard.padding(.top, 14)
                windowCards.padding(.top, 14)
                Spacer(minLength: 120)
            }
            .padding(.horizontal, 16).padding(.top, 18)
        }
        .background(AppPalette.background)
    }

    private var dayPicker: some View {
        HStack(spacing: 10) {
            ForEach(Array([C.t("map.dayToday"), "8/26", "8/25"].enumerated()), id: \.offset) { index, label in
                Button { selectedDay = index } label: {
                    Text(label).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedDay == index ? .white : AppPalette.muted)
                        .frame(width: 58, height: 40)
                        .background(selectedDay == index ? AppPalette.ink : .white)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(selectedDay == index ? 0 : 0.035), radius: 10, y: 5)
                }.buttonStyle(.plain)
            }
        }
    }

    private var chartCard: some View {
        VStack(spacing: 0) {
            EnergyMapChart().frame(height: 235)
            Text(C.t("map.trendNote"))
                .font(.system(size: 12)).foregroundStyle(AppPalette.faint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 22).padding(.bottom, 20)
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var windowCards: some View {
        HStack(alignment: .top, spacing: 10) {
            insightCard(eyebrow: C.t("map.bestFocus"), range: C.t("map.bestRange"),
                        note: C.t("map.bestNote"),
                        color: Color(red: 176 / 255, green: 218 / 255, blue: 132 / 255))
            insightCard(eyebrow: C.t("map.lowWindow"), range: C.t("map.lowRange"),
                        note: C.t("map.lowNote"), color: AppPalette.blue)
        }
    }

    private func insightCard(eyebrow: String, range: String, note: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow).font(.system(size: 10, weight: .bold)).tracking(1.2)
                .foregroundStyle(AppPalette.muted).padding(.horizontal, 11)
                .frame(height: 28).background(color.opacity(0.82)).clipShape(Capsule())
            Text(range).font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundStyle(AppPalette.ink)
            Text(note).font(.system(size: 12)).foregroundStyle(AppPalette.muted)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .padding(16).background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct EnergyMapChart: View {
    private let labels = ["08", "10", "12", "14", "16", "18", "20"]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let left: CGFloat = 29
            let right = width - 28
            let observedEnd = left + (right - left) * 0.69

            ZStack {
                RadialGradient(colors: [AppPalette.green.opacity(0.24), AppPalette.green.opacity(0)],
                               center: .topTrailing, startRadius: 5, endRadius: 135)
                observedPath(left: left, end: observedEnd)
                    .stroke(AppPalette.ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                estimatedPath(start: observedEnd, right: right)
                    .stroke(AppPalette.faint.opacity(0.8),
                            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [2, 7]))
                Text(C.t("map.deepWork")).font(.system(size: 11)).foregroundStyle(AppPalette.muted)
                    .position(x: width * 0.33, y: 45)
                Text(C.t("map.meetings")).font(.system(size: 11)).foregroundStyle(AppPalette.muted)
                    .position(x: width * 0.69, y: 155)
                Text(C.t("map.currentStatus")).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 31).background(AppPalette.green)
                    .clipShape(Capsule()).position(x: observedEnd, y: 99)
                Circle().fill(AppPalette.green).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.white, lineWidth: 2)).position(x: observedEnd, y: 142)
                HStack {
                    ForEach(labels, id: \.self) { label in
                        Text(label).font(.system(size: 10)).foregroundStyle(AppPalette.faint)
                        if label != labels.last { Spacer() }
                    }
                }
                .padding(.horizontal, 27).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 20)
            }
        }
    }

    private func observedPath(left: CGFloat, end: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: left, y: 132))
            path.addCurve(to: CGPoint(x: left + 72, y: 68),
                          control1: CGPoint(x: left + 22, y: 77), control2: CGPoint(x: left + 45, y: 58))
            path.addCurve(to: CGPoint(x: end, y: 142),
                          control1: CGPoint(x: left + 116, y: 75), control2: CGPoint(x: end - 70, y: 139))
        }
    }

    private func estimatedPath(start: CGFloat, right: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: start, y: 142))
            path.addCurve(to: CGPoint(x: right, y: 121),
                          control1: CGPoint(x: start + 28, y: 151), control2: CGPoint(x: right - 20, y: 126))
        }
    }
}

#Preview { MapView() }
