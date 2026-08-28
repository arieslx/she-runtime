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
            Button(C.t("today.languageButton")) {}
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
            Text(C.t("today.greeting")).font(.system(size: 34, weight: .heavy)).tracking(-0.5)
            Text(C.t("today.updatedAt"))
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
                Text(C.t("today.energyEyebrow"))
                    .font(.system(size: 10, weight: .bold)).tracking(2.4)
                    .foregroundStyle(Color(red: 201 / 255, green: 201 / 255, blue: 194 / 255))
                Text(tier.title)
                    .font(.system(size: 62, weight: .black, design: .serif))
                    .padding(.top, 10)
                Text("\(tier.english) · \(String(format: C.t("today.tierCountFormat"), tier.rawValue + 1))")
                    .font(.system(size: 19, weight: .semibold, design: .serif).italic())
                    .foregroundStyle(AppPalette.faint).padding(.top, 2)
                EnergyRuler(selection: $tier).padding(.top, 22)
                Text(C.t("today.energyBasis"))
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
                Text(C.t("today.suggestionLabel"))
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
            metric(C.t("today.metricSleepShort"), "7h 42", "m")
            Divider().frame(height: 48)
            metric("HRV", "46", "ms")
            Divider().frame(height: 48)
            metric(C.t("today.metricRestHRShort"), "58", "bpm")
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
                    Text(C.t("today.mapTitle")).font(.system(size: 25, weight: .semibold, design: .serif))
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
                Text(C.t("today.trendNote")).font(.system(size: 12)).foregroundStyle(AppPalette.faint)
            }
        }
        .padding(24).background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous)).clipped()
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(C.t("today.todayTitle")).font(.system(size: 23, weight: .semibold, design: .serif))
                Spacer()
                Text(C.t("today.eventsCount")).font(.system(size: 10, weight: .bold)).tracking(1.6).foregroundStyle(AppPalette.faint)
            }
            ForEach(Array(TodayMock.events.suffix(3).enumerated()), id: \.element.id) { index, event in
                HStack(alignment: .top, spacing: 14) {
                    Text(event.time).font(.system(size: 11, weight: .semibold)).foregroundStyle(AppPalette.faint)
                        .frame(width: 38, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(eventTitle(index)).font(.system(size: 15, weight: .bold))
                        Text(eventNote(index)).font(.system(size: 12)).foregroundStyle(AppPalette.muted)
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

    private func eventTitle(_ index: Int) -> String {
        [C.t("today.events.meetingTitle"), C.t("today.events.voiceTitle"), C.t("today.events.walkTitle")][index]
    }

    private func eventNote(_ index: Int) -> String {
        [C.t("today.events.meetingNote"), C.t("today.events.voiceNote"), C.t("today.events.walkNote")][index]
    }
}

private struct EnergyRuler: View {
    @Binding var selection: EnergyTier

    var body: some View {
        GeometryReader { geo in
            let usableWidth = max(0, geo.size.width - 34)
            let x = 17 + usableWidth * CGFloat(selection.rawValue) / 4
            ZStack(alignment: .topLeading) {
                Text(C.t("today.now")).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
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
    private var key: String { ["low", "dipping", "steady", "good", "full"][rawValue] }
    var title: String { C.t("today.tiers.\(key).title") }
    var english: String { C.t("today.tiers.\(key).english") }
    var asset: String { "MascotTier\(rawValue + 1)" }
    var imageWidth: CGFloat { [142, 140, 148, 150, 130][rawValue] }
    var imageOffset: CGFloat { [-13, -23, -60, -47, -59][rawValue] }
    var suggestionTitle: String { C.t("today.tiers.\(key).suggestionTitle") }
    var suggestionBody: String { C.t("today.tiers.\(key).suggestionBody") }
    var aura: Color {
        [Color(red: 232 / 255, green: 131 / 255, blue: 126 / 255).opacity(0.75),
         Color(red: 240 / 255, green: 154 / 255, blue: 107 / 255).opacity(0.75),
         Color(red: 192 / 255, green: 226 / 255, blue: 144 / 255).opacity(0.75),
         Color(red: 143 / 255, green: 210 / 255, blue: 74 / 255).opacity(0.75),
         AppPalette.green.opacity(0.75)][rawValue]
    }
}

#Preview { TodayView() }
