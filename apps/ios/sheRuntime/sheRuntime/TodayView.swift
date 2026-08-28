import SwiftUI
import SwiftData

struct TodayView: View {
    private let onProfile: () -> Void
    @State private var tier: EnergyTier = .low
    @Query(sort: \TimelineRecord.createdAt) private var savedRecords: [TimelineRecord]

    init(onProfile: @escaping () -> Void = {}) { self.onProfile = onProfile }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                greeting
                VStack(spacing: 14) {
                    energyHero
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
            ProfileMenuButton(action: onProfile)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(C.t("today.greeting")).font(.system(size: 34, weight: .heavy)).tracking(-0.5)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(updatedAtText(context.date))
                    .font(.system(size: 11, weight: .bold)).tracking(1.6)
                    .foregroundStyle(AppPalette.faint)
            }
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
        .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var timelineCard: some View {
        let events = todayTimelineEvents
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(C.t("today.todayTitle")).font(.system(size: 23, weight: .semibold, design: .serif))
                Spacer()
                Text(eventsCountText(events.count)).font(.system(size: 10, weight: .bold)).tracking(1.6).foregroundStyle(AppPalette.faint)
            }
            ForEach(Array(events.suffix(3).enumerated()), id: \.element.id) { index, event in
                HStack(alignment: .top, spacing: 14) {
                    Text(event.time).font(.system(size: 11, weight: .semibold)).foregroundStyle(AppPalette.faint)
                        .frame(width: 38, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        if let iconAsset = event.iconAsset {
                            Image(iconAsset).renderingMode(.template).resizable().scaledToFit()
                                .foregroundStyle(AppPalette.ink)
                                .frame(width: 17, height: 17)
                                .accessibilityLabel(C.t("today.voiceIconAccessibility"))
                        } else {
                            Text(event.title).font(.system(size: 15, weight: .bold))
                        }
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

    private var todayTimelineEvents: [TimelineDisplayEvent] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        let mockEvents = TodayMock.events.map { event in
            TimelineDisplayEvent(
                id: event.id.uuidString,
                createdAt: calendar.todayDate(hourMinute: event.time),
                time: event.time,
                title: event.title,
                note: event.note,
                iconAsset: nil
            )
        }

        let voiceEvents = savedRecords
            .filter { calendar.isDateInToday($0.createdAt) && $0.saveStatus == TimelineRecordStatus.saved }
            .map { record in
                TimelineDisplayEvent(
                    id: record.id.uuidString,
                    createdAt: record.createdAt,
                    time: formatter.string(from: record.createdAt),
                    title: record.eventType,
                    note: "“\(record.confirmedText)”",
                    iconAsset: record.eventType == TimelineRecordType.voiceCheckIn ? "Microphone" : nil
                )
            }

        return (mockEvents + voiceEvents).sorted { $0.createdAt < $1.createdAt }
    }

    private func eventsCountText(_ count: Int) -> String {
        AppLanguage.current == .en ? "\(count) EVENTS" : "\(count) 个事件"
    }

    private func updatedAtText(_ date: Date) -> String {
        let locale = AppLanguage.current == .en ? Locale(identifier: "en_US") : Locale(identifier: "zh_CN")
        let weekday = DateFormatter()
        weekday.locale = locale
        weekday.dateFormat = AppLanguage.current == .en ? "EEE" : "EEEE"
        let day = DateFormatter()
        day.locale = locale
        day.dateFormat = AppLanguage.current == .en ? "MMM d" : "M月d日"
        let time = DateFormatter()
        time.locale = locale
        time.dateFormat = "HH:mm"
        return String(
            format: C.t("today.updatedAtFormat"),
            weekday.string(from: date), day.string(from: date), time.string(from: date)
        )
    }
}

private struct TimelineDisplayEvent: Identifiable {
    let id: String
    let createdAt: Date
    let time: String
    let title: String
    let note: String
    let iconAsset: String?
}

private extension Calendar {
    func todayDate(hourMinute: String) -> Date {
        let pieces = hourMinute.split(separator: ":").compactMap { Int($0) }
        var components = dateComponents([.year, .month, .day], from: Date())
        components.hour = pieces.first ?? 0
        components.minute = pieces.dropFirst().first ?? 0
        return date(from: components) ?? Date()
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
                .padding(.horizontal, 17)
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

private enum EnergyTier: Int, CaseIterable, Identifiable {
    case low, dipping, steady, good, full
    var id: Int { rawValue }
    private var key: String { ["low", "dipping", "steady", "good", "full"][rawValue] }
    var title: String { C.t("today.tiers.\(key).title") }
    var english: String { C.t("today.tiers.\(key).english") }
    var asset: String { "MascotTier\(rawValue + 1)" }
    var imageWidth: CGFloat { [142, 140, 148, 150, 130][rawValue] }
    var imageOffset: CGFloat { [-13, -23, -60, -47, -59][rawValue] }
}

#Preview {
    TodayView()
        .modelContainer(for: [Item.self, TimelineRecord.self], inMemory: true)
}
