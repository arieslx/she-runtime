import SwiftUI

struct TodayView: View {
    private let onProfile: () -> Void
    @State private var tier: EnergyTier = .low

    init(onProfile: @escaping () -> Void = {}) { self.onProfile = onProfile }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                greeting
                VStack(spacing: 14) {
                    energyHero
                    suggestionCard
                    metricsCard
                    mapPreview
                    timelineCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 58)
                .padding(.bottom, 60)
            }
        }
        .scrollIndicators(.hidden)
        .background(AppPalette.background)
    }

    private var header: some View {
        HStack {
            Image("AppLogo").resizable().scaledToFit()
                .frame(width: 82, height: 44, alignment: .leading)
            Spacer()
            Button("EN") {}
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AppPalette.ink)
                .frame(width: 42, height: 42)
                .background(.white).clipShape(Circle())
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)
            Button(action: onProfile) {
                Image("ProfileAvatar").resizable().scaledToFill()
                    .frame(width: 42, height: 42).clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Hey~").font(.system(size: 34, weight: .heavy)).tracking(-0.5)
            Text("THU · AUG 27 · UPD 11:32")
                .font(.system(size: 11, weight: .bold)).tracking(1.6)
                .foregroundStyle(AppPalette.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 15)
    }

    private var energyHero: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                Text("CURRENT ENERGY")
                    .font(.system(size: 10, weight: .bold)).tracking(2.4)
                    .foregroundStyle(Color(red: 201 / 255, green: 201 / 255, blue: 194 / 255))
                Text(tier.title)
                    .font(.system(size: 62, weight: .black, design: .serif))
                    .padding(.top, 10)
                Text("\(tier.english) · \(tier.rawValue + 1) of 5")
                    .font(.system(size: 19, weight: .semibold, design: .serif).italic())
                    .foregroundStyle(AppPalette.faint).padding(.top, 2)
                EnergyRuler(selection: $tier).padding(.top, 22)
                Text("基于今天的主动记录与最近事件")
                    .font(.system(size: 12)).foregroundStyle(AppPalette.faint)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(tier.asset).resizable().scaledToFit()
                .frame(width: tier.imageWidth)
                .offset(x: 6, y: tier.imageOffset)
        }
        .padding(24)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var suggestionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SUGGESTION")
                    .font(.system(size: 10, weight: .bold)).tracking(1.2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(AppPalette.blue).clipShape(Capsule())
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(Color(red: 241 / 255, green: 241 / 255, blue: 238 / 255))
                    .clipShape(Circle())
            }
            Text(tier.suggestionTitle)
                .font(.system(size: 21, weight: .heavy)).tracking(-0.2)
                .padding(.top, 18)
            Text(tier.suggestionBody)
                .font(.system(size: 14)).foregroundStyle(AppPalette.muted)
                .lineSpacing(8).padding(.top, 9)
        }
        .padding(24).background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var metricsCard: some View {
        HStack(spacing: 0) {
            metric("SLEEP", "7h 42", "m")
            Divider().frame(height: 48)
            metric("HRV", "46", "ms")
            Divider().frame(height: 48)
            metric("REST HR", "58", "bpm")
        }
        .padding(.vertical, 21).padding(.horizontal, 8)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func metric(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 7) {
            Text(label).font(.system(size: 9, weight: .bold)).tracking(1.8).foregroundStyle(AppPalette.faint)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value).font(.system(size: 24, weight: .semibold, design: .serif))
                Text(unit).font(.system(size: 10)).foregroundStyle(AppPalette.faint)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var mapPreview: some View {
        ZStack(alignment: .topLeading) {
            Circle().fill(tier.aura).frame(width: 250, height: 250)
                .blur(radius: 28).offset(x: 100, y: -120)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Energy Map").font(.system(size: 25, weight: .semibold, design: .serif))
                    Spacer()
                    Image(systemName: "arrow.up.right").frame(width: 40, height: 40)
                        .background(Color(red: 241 / 255, green: 241 / 255, blue: 238 / 255)).clipShape(Circle())
                }
                EnergyMiniCurve().frame(height: 120)
                HStack {
                    ForEach(["08", "10", "12", "14", "16", "18", "20"], id: \.self) { hour in
                        Text(hour).font(.system(size: 10, weight: .medium)).foregroundStyle(AppPalette.faint)
                        if hour != "20" { Spacer() }
                    }
                }
                Text("实线为观察，虚线为估计趋势").font(.system(size: 12)).foregroundStyle(AppPalette.faint)
            }
        }
        .padding(24).background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous)).clipped()
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today").font(.system(size: 23, weight: .semibold, design: .serif))
                Spacer()
                Text("5 EVENTS").font(.system(size: 10, weight: .bold)).tracking(1.6).foregroundStyle(AppPalette.faint)
            }
            ForEach(Array(TodayMock.events.suffix(3).enumerated()), id: \.element.id) { index, event in
                HStack(alignment: .top, spacing: 14) {
                    Text(event.time).font(.system(size: 11, weight: .semibold)).foregroundStyle(AppPalette.faint)
                        .frame(width: 38, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.title).font(.system(size: 15, weight: .bold))
                        Text(event.note).font(.system(size: 12)).foregroundStyle(AppPalette.muted)
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
                if index < 2 { Divider() }
            }
        }
        .padding(24).background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct EnergyRuler: View {
    @Binding var selection: EnergyTier

    var body: some View {
        GeometryReader { geo in
            let usableWidth = max(0, geo.size.width - 34)
            let x = 17 + usableWidth * CGFloat(selection.rawValue) / 4
            ZStack(alignment: .topLeading) {
                Text("Now").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).frame(height: 30)
                    .background(AppPalette.green).clipShape(Capsule())
                    .shadow(color: AppPalette.green.opacity(0.35), radius: 6, y: 4)
                    .position(x: x, y: 15)
                Rectangle().fill(AppPalette.ink).frame(width: 1.5, height: 14).position(x: x, y: 38)
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<29, id: \.self) { index in
                        Rectangle()
                            .fill(index == selection.rawValue * 7 ? AppPalette.ink : Color(red: 221 / 255, green: 221 / 255, blue: 214 / 255))
                            .frame(width: index % 7 == 0 ? 1.5 : 1, height: index % 7 == 0 ? 18 : 10)
                        if index < 28 { Spacer() }
                    }
                }
                .frame(height: 18).offset(y: 45)
                HStack(spacing: 0) {
                    ForEach(EnergyTier.allCases) { item in
                        Button { selection = item } label: {
                            Text(item.title)
                                .font(.system(size: 11, weight: selection == item ? .bold : .medium))
                                .foregroundStyle(selection == item ? AppPalette.ink : AppPalette.faint)
                                .frame(maxWidth: .infinity, alignment: item == .low ? .leading : item == .full ? .trailing : .center)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .offset(y: 72)
            }
        }
        .frame(height: 96)
    }
}

private struct EnergyMiniCurve: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: CGPoint(x: 0, y: geo.size.height * 0.62))
                path.addCurve(to: CGPoint(x: geo.size.width * 0.7, y: geo.size.height * 0.78),
                              control1: CGPoint(x: geo.size.width * 0.18, y: geo.size.height * 0.12),
                              control2: CGPoint(x: geo.size.width * 0.42, y: geo.size.height * 0.76))
                path.addCurve(to: CGPoint(x: geo.size.width, y: geo.size.height * 0.58),
                              control1: CGPoint(x: geo.size.width * 0.82, y: geo.size.height * 0.84),
                              control2: CGPoint(x: geo.size.width * 0.92, y: geo.size.height * 0.62))
            }
            .stroke(AppPalette.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}

private enum EnergyTier: Int, CaseIterable, Identifiable {
    case low, dipping, steady, good, full
    var id: Int { rawValue }
    var title: String { ["低", "偏低", "平稳", "良好", "充沛"][rawValue] }
    var english: String { ["Low", "Dipping", "Steady", "Good", "Full"][rawValue] }
    var asset: String { "MascotTier\(rawValue + 1)" }
    var imageWidth: CGFloat { [142, 140, 148, 150, 130][rawValue] }
    var imageOffset: CGFloat { [-13, -23, -60, -47, -59][rawValue] }
    var suggestionTitle: String { ["先把恢复放在第一位", "放慢节奏，减少消耗", "保持当前节奏", "适合推进重要任务", "进入深度工作窗口"][rawValue] }
    var suggestionBody: String {
        ["暂停新任务，小睡 20 分钟或出门走走；今天不适合再安排高消耗事项。",
         "只处理轻量事务，避免连续会议；90 分钟内安排一次 15 分钟的休息。",
         "下午避免再排 90 分钟以上的连续会议；状态下降时，步行 15–30 分钟恢复最稳。",
         "把需要专注的事排进接下来两小时，注意会议不要连排。",
         "现在是深度工作的黄金窗口：屏蔽打扰，专注 90 分钟。"][rawValue]
    }
    var aura: Color {
        [Color(red: 232 / 255, green: 131 / 255, blue: 126 / 255).opacity(0.75),
         Color(red: 240 / 255, green: 154 / 255, blue: 107 / 255).opacity(0.75),
         Color(red: 192 / 255, green: 226 / 255, blue: 144 / 255).opacity(0.75),
         Color(red: 143 / 255, green: 210 / 255, blue: 74 / 255).opacity(0.75),
         AppPalette.green.opacity(0.75)][rawValue]
    }
}

#Preview { TodayView() }
