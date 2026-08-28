import SwiftUI
import SwiftData

@MainActor
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var energyMap: EnergyMapViewModel
    private let onProfile: () -> Void
    @Query(sort: \TimelineRecord.createdAt) private var savedRecords: [TimelineRecord]
    @State private var editingRecord: TimelineRecord?
    @State private var editingText = ""
    @State private var showsAllEvents = false

    init(energyMap: EnergyMapViewModel, onProfile: @escaping () -> Void = {}) {
        _energyMap = ObservedObject(wrappedValue: energyMap)
        self.onProfile = onProfile
    }

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
        .task { await energyMap.refreshTodayState() }
        .sheet(item: $editingRecord) { record in
            EditableTextPanel(
                text: $editingText,
                date: record.createdAt,
                isHidden: record.isHidden,
                onToggleHidden: {
                    record.isHidden.toggle()
                    try? modelContext.save()
                },
                onDelete: {
                    modelContext.delete(record)
                    try? modelContext.save()
                    editingRecord = nil
                },
                onClose: { editingRecord = nil },
                onConfirm: {
                    let value = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty {
                        record.confirmedText = value
                        try? modelContext.save()
                    }
                    editingRecord = nil
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsAllEvents) {
            TodayEventsPanel(events: todayTimelineEvents, onClose: { showsAllEvents = false })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
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
        let tier = energyMap.currentEnergyState.displayTier
        return ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                Text(C.t("today.energyEyebrow"))
                    .font(.system(size: 10, weight: .bold)).tracking(2.4)
                    .foregroundStyle(Color(red: 201 / 255, green: 201 / 255, blue: 194 / 255))
                if let tier {
                    Text(tier.title)
                        .font(.system(size: 62, weight: .black, design: .serif))
                        .padding(.top, 10)
                    Text("\(tier.english) · \(String(format: C.t("today.tierCountFormat"), tier.rawValue + 1))")
                        .font(.system(size: 19, weight: .semibold, design: .serif).italic())
                        .foregroundStyle(AppPalette.faint).padding(.top, 2)
                } else {
                    Text(C.t("map.waitingForData"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppPalette.faint)
                        .padding(.top, 12)
                }
                EnergyRuler(selection: tier).padding(.top, 22)
                Text(C.t("today.energyBasis"))
                    .font(.system(size: 12)).foregroundStyle(AppPalette.faint)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let tier {
                Image(tier.asset).resizable().scaledToFit()
                    .frame(width: tier.imageWidth)
                    .offset(x: 6, y: tier.imageOffset)
            }
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
                Button { showsAllEvents = true } label: {
                    HStack(spacing: 4) {
                        Text(eventsCountText(events.count))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(AppPalette.faint)
                }
                .buttonStyle(.plain)
            }
            if events.isEmpty {
                Text(C.t("today.allEventsEmpty"))
                    .font(.system(size: 13))
                    .foregroundStyle(AppPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            } else {
                let visibleEvents = Array(events.suffix(3))
                ForEach(Array(visibleEvents.enumerated()), id: \.element.id) { index, event in
                    Button {
                        guard let record = event.record else { return }
                        editingText = record.confirmedText
                        editingRecord = record
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Text(event.time)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppPalette.faint)
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
                                    .lineLimit(3, reservesSpace: false)
                                    .truncationMode(.tail)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(event.record == nil)
                    .padding(.vertical, 10)
                    if index < visibleEvents.count - 1 { Divider() }
                }
            }
        }
        .padding(24).background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var todayTimelineEvents: [TimelineDisplayEvent] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"

        let mockEvents: [TimelineDisplayEvent] = {
#if DEBUG
            return TodayMock.events.map { event in
                TimelineDisplayEvent(
                    id: event.id.uuidString,
                    createdAt: calendar.todayDate(hourMinute: event.time),
                    time: event.time,
                    title: event.title,
                    note: event.note,
                    iconAsset: nil,
                    record: nil
                )
            }
#else
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                return TodayMock.events.map { event in
                    TimelineDisplayEvent(
                        id: event.id.uuidString,
                        createdAt: calendar.todayDate(hourMinute: event.time),
                        time: event.time,
                        title: event.title,
                        note: event.note,
                        iconAsset: nil,
                        record: nil
                    )
                }
            }
            return []
#endif
        }()

        let voiceEvents = savedRecords
            .filter {
                calendar.isDateInToday($0.createdAt)
                    && $0.saveStatus == TimelineRecordStatus.saved
                    && !$0.isHidden
            }
            .map { record in
                TimelineDisplayEvent(
                    id: record.id.uuidString,
                    createdAt: record.createdAt,
                    time: formatter.string(from: record.createdAt),
                    title: record.eventType,
                    note: "“\(record.confirmedText)”",
                    iconAsset: record.eventType == TimelineRecordType.voiceCheckIn ? "Microphone" : nil,
                    record: record
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

private struct TodayEventsPanel: View {
    let events: [TimelineDisplayEvent]
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if events.isEmpty {
                    Text(C.t("today.allEventsEmpty"))
                        .foregroundStyle(AppPalette.muted)
                } else {
                    ForEach(events) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(event.time)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(AppPalette.faint)
                                Spacer()
                                if event.record != nil {
                                    Text(C.t("today.allEventsSaved"))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(AppPalette.green)
                                }
                            }
                            Text(event.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppPalette.ink)
                            Text(event.note)
                                .font(.system(size: 13))
                                .foregroundStyle(AppPalette.muted)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(C.t("today.allEventsTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}

private struct TimelineDisplayEvent: Identifiable {
    let id: String
    let createdAt: Date
    let time: String
    let title: String
    let note: String
    let iconAsset: String?
    let record: TimelineRecord?
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
    let selection: EnergyState?

    var body: some View {
        GeometryReader { geo in
            let usableWidth = max(0, geo.size.width - 34)
            let x = selection.map { 17 + usableWidth * CGFloat($0.rawValue) / 4 }
            ZStack(alignment: .topLeading) {
                if let x {
                    Text(C.t("today.now")).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 30)
                        .background(AppPalette.green).clipShape(Capsule())
                        .shadow(color: AppPalette.green.opacity(0.35), radius: 6, y: 4)
                        .position(x: x, y: 15)
                    Rectangle().fill(AppPalette.ink).frame(width: 1.5, height: 14).position(x: x, y: 38)
                }
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<29, id: \.self) { index in
                        Rectangle()
                            .fill(index == selection.map({ $0.rawValue * 7 }) ? AppPalette.ink : Color(red: 221 / 255, green: 221 / 255, blue: 214 / 255))
                            .frame(width: index % 7 == 0 ? 1.5 : 1, height: index % 7 == 0 ? 18 : 10)
                        if index < 28 { Spacer() }
                    }
                }
                .padding(.horizontal, 17)
                .frame(height: 18).offset(y: 45)
                HStack(spacing: 0) {
                    ForEach(EnergyState.displayCases) { item in
                        Text(item.title)
                            .font(.system(size: 11, weight: selection == item ? .bold : .medium))
                            .foregroundStyle(selection == item ? AppPalette.ink : AppPalette.faint)
                            .frame(maxWidth: .infinity, alignment: item == .low ? .leading : item == .full ? .trailing : .center)
                    }
                }
                .offset(y: 72)
            }
        }
        .frame(height: 96)
    }
}

private extension EnergyState {
    var displayTier: EnergyState? { self == .insufficientData ? nil : self }
    private var key: String { ["low", "dipping", "steady", "good", "full"][rawValue] }
    var title: String { C.t("today.tiers.\(key).title") }
    var english: String { C.t("today.tiers.\(key).english") }
    var asset: String { "MascotTier\(rawValue + 1)" }
    var imageWidth: CGFloat { [142, 140, 148, 150, 130][rawValue] }
    var imageOffset: CGFloat { [-13, -23, -60, -47, -59][rawValue] }
}

#Preview {
    TodayView(energyMap: AppServices().energyMap)
        .modelContainer(for: [Item.self, TimelineRecord.self], inMemory: true)
}
