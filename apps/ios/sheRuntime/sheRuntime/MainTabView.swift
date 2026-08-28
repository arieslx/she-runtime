import SwiftUI
import SwiftData

private enum MainSection: Int, CaseIterable {
    case today, map, insights, ask, profile

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .map: "waveform.path.ecg"
        case .insights: "sparkles"
        case .ask: "bubble.left"
        case .profile: "person"
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject private var appServices: AppServices
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: MainSection = {
        let page = Int(ProcessInfo.processInfo.environment["SHOT_PAGE"] ?? "") ?? 0
        return MainSection(rawValue: min(page, 4)) ?? .today
    }()
    @StateObject private var voiceCapture = VoiceCaptureViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            page.padding(.bottom, 82)

            LinearGradient(colors: [AppPalette.background.opacity(0), AppPalette.background], startPoint: .top, endPoint: .bottom)
                .frame(height: 112)
                .allowsHitTesting(false)

            dock.padding(.horizontal, 16).padding(.bottom, 8)

            if selection != .ask && selection != .profile {
                voiceControl
                    .offset(x: voiceControlOffsetX, y: -82)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
        .background(AppPalette.background.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if case .reviewing(let draft) = voiceCapture.state {
                reviewOverlay(draft: draft)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: voiceCapture.state.animationKey)
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            voiceCapture.handleSceneInactive()
        }
        .onChange(of: selection) { _, newValue in
            if newValue == .ask {
                voiceCapture.handleVoiceSurfaceDismissed()
            }
        }
        .onChange(of: appServices.stopWatchBLE.streamSnapshot) { _, snapshot in
            appServices.stopWatchAudioPipeline.handleCompletedStream(snapshot, modelContext: modelContext)
        }
    }

    @ViewBuilder private var page: some View {
        switch selection {
        case .today: TodayView { openProfile() }
        case .map: MapView { openProfile() }
        case .insights: InsightsView { openProfile() }
        case .ask: AskView { openProfile() }
        case .profile: ProfileView()
        }
    }

    private var dock: some View {
        HStack {
            ForEach([MainSection.today, .map, .insights, .ask], id: \.rawValue) { item in
                Button { selection = item } label: {
                    Image(systemName: item.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(selection == item ? .white : AppPalette.faint)
                        .frame(width: 50, height: 50)
                        .background(selection == item ? AppPalette.ink : .clear)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 66)
        .background(.white)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
    }

    @ViewBuilder private var voiceControl: some View {
        switch voiceCapture.state {
        case .idle:
            idleVoiceButton
        case .failed(let message):
            failedVoiceTooltip(message: message)
        case .recording(let startedAt):
            recordingVoiceButton(startedAt: startedAt)
        case .processing(let message):
            processingVoiceButton(message: message)
        case .reviewing:
            EmptyView()
        case .saved:
            savedVoiceTooltip
        }
    }

    private var voiceControlOffsetX: CGFloat {
        switch voiceCapture.state {
        case .idle:
            72
        case .saved:
            32
        case .recording, .processing, .reviewing, .failed:
            0
        }
    }

    private var idleVoiceButton: some View {
        Button {
            Task { await voiceCapture.startRecording() }
        } label: {
            ZStack(alignment: .leading) {
                Capsule().fill(AppPalette.ink)
                Image("MascotDance")
                    .resizable().scaledToFit()
                    .frame(width: 54, height: 60)
                    .offset(x: 7, y: -5)
                Image("Microphone").renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: 19, height: 19)
                    .offset(x: 82)
            }
            .frame(width: 116, height: 52)
            .shadow(color: .black.opacity(0.25), radius: 12, y: 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(C.t("today.voiceIconAccessibility"))
    }

    private func recordingVoiceButton(startedAt: Date) -> some View {
        Button { voiceCapture.stopRecordingAndTranscribe() } label: {
            TimelineView(.animation) { context in
                VStack(spacing: 22) {
                    VoicePowerWaveform(date: context.date, level: voiceCapture.meterLevel)
                        .frame(width: 170, height: 32)

                    HStack(spacing: 18) {
                        Text("正在记录 · 点击保存")
                            .font(.system(size: 20, weight: .heavy))
                        Text(recordingTimeText(startedAt: startedAt, now: context.date))
                            .font(.system(size: 20, weight: .heavy, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .frame(height: 104)
                .background(AppPalette.ink)
                .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
            }
            .frame(width: 344, height: 104)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("正在记录，点击保存")
    }

    private func processingVoiceButton(message: String) -> some View {
        HStack(spacing: 12) {
            ProgressView()
                .tint(.white)
            Text(message)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 24)
        .frame(width: 286, height: 72)
        .background(AppPalette.ink)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }

    private var savedVoiceTooltip: some View {
        ZStack(alignment: .trailing) {
            Text("已记录 · 已加入今天的时间轴")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.leading, 24)
                .padding(.trailing, 96)
                .frame(height: 62)
                .background(AppPalette.ink)
                .clipShape(Capsule())

            ZStack(alignment: .leading) {
                Capsule().fill(AppPalette.ink)
                Image("MascotDance")
                    .resizable().scaledToFit()
                    .frame(width: 48, height: 52)
                    .offset(x: 18, y: 11)
                Image("Microphone").renderingMode(.template).resizable().scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .offset(x: 83)
            }
            .frame(width: 124, height: 62)
            .offset(x: 56)
        }
        .frame(width: 326, height: 74)
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }

    private func failedVoiceTooltip(message: String) -> some View {
        Text(message)
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(.white)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 22)
            .frame(width: 300, height: 68)
            .background(AppPalette.ink)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }

    private func reviewOverlay(draft: VoiceReviewDraft) -> some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.36)
                .ignoresSafeArea()

            EditableTextPanel(
                text: reviewTextBinding,
                date: nil,
                isHidden: false,
                onToggleHidden: nil,
                onDelete: nil,
                onClose: voiceCapture.cancelReview,
                onConfirm: { voiceCapture.saveReviewedVoiceRecord(modelContext: modelContext) }
            )
            .padding(.horizontal, 15)
            .padding(.bottom, 0)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var reviewTextBinding: Binding<String> {
        Binding(
            get: {
                guard case .reviewing(let draft) = voiceCapture.state else { return "" }
                return draft.confirmedText
            },
            set: { newValue in
                voiceCapture.updateDraftText(newValue)
            }
        )
    }

    private func recordingTimeText(startedAt: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(startedAt)))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    private func openProfile() {
        voiceCapture.handleVoiceSurfaceDismissed()
        selection = .profile
    }
}

private struct VoicePowerWaveform: View {
    let date: Date
    let level: Double

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<24, id: \.self) { index in
                let phase = date.timeIntervalSinceReferenceDate * 4 + Double(index) * 0.58
                let floor = 8.0 + abs(sin(phase)) * 4.0
                let response = min(1, max(0, level)) * (index.isMultiple(of: 5) ? 25.0 : 18.0)
                let height = floor + response * (0.48 + 0.52 * abs(sin(phase)))
                Capsule()
                    .fill(.white)
                    .frame(width: 5, height: CGFloat(height))
            }
        }
    }
}

private struct WrappingTagLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let maxWidth = proposal.width ?? 0
        let rows = rows(maxWidth: maxWidth, subviews: subviews)
        let height = rows.reduce(CGFloat.zero) { partial, row in
            partial + row.height
        } + CGFloat(max(0, rows.count - 1)) * verticalSpacing
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        var y = bounds.minY
        for row in rows(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                let size = subviews[item.index].sizeThatFits(.unspecified)
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private func rows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        let effectiveWidth = max(maxWidth, 1)

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = current.items.isEmpty
                ? size.width
                : current.width + horizontalSpacing + size.width

            if nextWidth > effectiveWidth && !current.items.isEmpty {
                rows.append(current)
                current = Row()
            }

            current.items.append(RowItem(index: index))
            current.width = current.items.count == 1 ? size.width : nextWidth
            current.height = max(current.height, size.height)
        }

        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }

    private struct Row {
        var items: [RowItem] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private struct RowItem {
        let index: Int
    }
}

enum AppPalette {
    static let green = Color(red: 104 / 255, green: 195 / 255, blue: 0)
    static let blue = Color(red: 174 / 255, green: 202 / 255, blue: 251 / 255)
    static let ink = Color(red: 22 / 255, green: 21 / 255, blue: 17 / 255)
    static let muted = Color(red: 138 / 255, green: 138 / 255, blue: 132 / 255)
    static let faint = Color(red: 181 / 255, green: 181 / 255, blue: 174 / 255)
    static let background = Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255)
}

#Preview {
    MainTabView()
        .modelContainer(for: [Item.self, TimelineRecord.self], inMemory: true)
}
