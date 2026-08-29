import SwiftUI
import SwiftData
import UIKit

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

    var copyKey: String {
        switch self {
        case .today: "today"
        case .map: "map"
        case .insights: "insights"
        case .ask: "ask"
        case .profile: "profile"
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
    @State private var isKeyboardVisible = false
    @State private var isCancelNoticeVisible = false
    @State private var cancelNoticeTask: Task<Void, Never>?
    @AppStorage("voiceCaptureCoachmarkSeen") private var hasSeenVoiceCaptureCoachmark = false
    @StateObject private var voiceCapture = VoiceCaptureViewModel()

    var body: some View {
        ZStack(alignment: .bottom) {
            page.padding(.bottom, isKeyboardVisible ? 0 : 82)

            if !isKeyboardVisible {
                LinearGradient(colors: [AppPalette.background.opacity(0), AppPalette.background], startPoint: .top, endPoint: .bottom)
                    .frame(height: voiceSurfaceHeight)
                    .allowsHitTesting(false)

                voiceDock
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
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
        .onChange(of: appServices.stopWatchBLE.streamSnapshot) { _, snapshot in
            appServices.stopWatchAudioPipeline.handleCompletedStream(snapshot, modelContext: modelContext)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .onDisappear {
            cancelNoticeTask?.cancel()
        }
    }

    @ViewBuilder private var page: some View {
        switch selection {
        case .today: TodayView(energyMap: appServices.energyMap) { openProfile() }
        case .map: MapView(viewModel: appServices.energyMap) { openProfile() }
        case .insights: InsightsView { openProfile() }
        case .ask: AskView { openProfile() }
        case .profile: ProfileView()
        }
    }

    private var voiceSurfaceHeight: CGFloat {
        switch voiceCapture.state {
        case .recording:
            324
        case .processing:
            324
        case .idle where shouldShowVoiceCoachmark:
            410
        case .idle, .reviewing, .saved, .failed:
            112
        }
    }

    @ViewBuilder private var voiceDock: some View {
        switch voiceCapture.state {
        case .recording(let startedAt):
            recordingVoiceDock(startedAt: startedAt)
        case .processing(let message):
            processingVoiceDock(message: message)
        case .idle, .saved, .failed, .reviewing:
            ZStack(alignment: .bottom) {
                dock

                if selection != .profile {
                    switch voiceCapture.state {
                    case .idle:
                        idleVoiceButton
                        if isCancelNoticeVisible {
                            cancelledVoiceTooltip
                                .offset(y: -74)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    case .saved:
                        savedVoiceTooltip
                            .offset(y: -74)
                    case .failed(let message):
                        idleVoiceButton
                        failedVoiceTooltip(message: message)
                            .offset(y: -74)
                    case .recording, .processing, .reviewing:
                        EmptyView()
                    }

                    if shouldShowVoiceCoachmark {
                        voiceCoachmark
                            .offset(y: -80)
                    }
                }
            }
        }
    }

    private var shouldShowVoiceCoachmark: Bool {
        guard !hasSeenVoiceCaptureCoachmark, selection != .profile else { return false }
        if case .idle = voiceCapture.state { return true }
        return false
    }

    private var dock: some View {
        dockItems(dark: false)
            .padding(.horizontal, 8)
            .frame(height: 66)
            .background(.white)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
    }

    private func dockItems(dark: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach([MainSection.today, .map], id: \.rawValue) { item in
                dockButton(item, dark: dark)
            }

            Color.clear
                .frame(width: 64, height: 50)
                .accessibilityHidden(true)

            ForEach([MainSection.insights, .ask], id: \.rawValue) { item in
                dockButton(item, dark: dark)
            }
        }
    }

    private func dockButton(_ item: MainSection, dark: Bool) -> some View {
        Button { selection = item } label: {
            Image(systemName: item.icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(
                    selection == item
                        ? Color.white
                        : (dark ? Color.white.opacity(0.48) : AppPalette.faint)
                )
                .frame(width: 46, height: 46)
                .background(
                    selection == item
                        ? (dark ? Color.white.opacity(0.14) : AppPalette.ink)
                        : Color.clear
                )
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(C.t("tabs.\(item.copyKey)"))
    }

    private var idleVoiceButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            startVoiceCapture()
        } label: {
            MascotMicrophoneMark(size: 64)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                .offset(x: -3, y: 2)
                .frame(width: 72, height: 72)
                .contentShape(Circle())
        }
        .buttonStyle(DockVoiceButtonStyle())
        .accessibilityLabel(C.t("voiceCapture.accessibility"))
        .accessibilityHint(C.t("voiceCapture.accessibilityHint"))
    }

    private func recordingVoiceDock(startedAt: Date) -> some View {
        TimelineView(.animation) { context in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    Text(C.t("voiceCapture.listening"))
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AppPalette.green)

                    Text(recordingTimeText(startedAt: startedAt, now: context.date))
                        .font(.system(size: 19, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.top, 6)

                    ZStack {
                        VoicePowerWaveform(
                            date: context.date,
                            level: voiceCapture.meterLevel,
                            color: AppPalette.green
                        )
                        .frame(width: 278, height: 56)

                        MascotMicrophoneMark(size: 102)
                    }
                    .frame(height: 108)
                    .padding(.top, 10)

                    Spacer(minLength: 12)

                    Button {
                        voiceCapture.stopRecordingAndTranscribe()
                    } label: {
                        Text(C.t("voiceCapture.finish"))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AppPalette.ink)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(.white)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                }
                .padding(.top, 24)
                .padding(.bottom, 20)

                Button {
                    cancelVoiceCapture()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.76))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                .padding(.top, 10)
                .accessibilityLabel(C.t("voiceCapture.cancel"))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 292)
            .background(AppPalette.ink)
            .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            .onTapGesture { }
            .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        }
    }

    private func processingVoiceDock(message: String) -> some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            Text(C.t("voiceCapture.processing"))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(AppPalette.green)

            ZStack {
                EnergyCollectionPulse(color: AppPalette.green)
                    .frame(width: 104, height: 104)
                MascotMicrophoneMark(size: 94)
            }

            HStack(spacing: 10) {
                ProgressView()
                    .tint(AppPalette.green)
                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.68))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .frame(height: 292)
        .background(AppPalette.ink)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .onTapGesture { }
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
    }

    private var voiceCoachmark: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                MascotMicrophoneMark(size: 68)

                VStack(alignment: .leading, spacing: 5) {
                    Text(C.t("voiceCapture.firstUseTitle"))
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(AppPalette.ink)

                    Text(C.t("voiceCapture.firstUseBody"))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppPalette.muted)
                        .lineSpacing(3)
                }
            }

            Button {
                startVoiceCapture()
            } label: {
                Text(C.t("voiceCapture.firstUseStart"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(AppPalette.green)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Button {
                hasSeenVoiceCaptureCoachmark = true
            } label: {
                Text(C.t("voiceCapture.firstUseLater"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 18, y: 8)
    }

    private var savedVoiceTooltip: some View {
        ZStack(alignment: .trailing) {
            Text(C.t("voiceCapture.savedEnergy"))
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.leading, 24)
                .padding(.trailing, 96)
                .frame(height: 62)
                .background(AppPalette.ink)
                .clipShape(Capsule())

            ZStack(alignment: .leading) {
                Capsule().fill(AppPalette.ink)
                ZStack {
                    EnergyCollectionPulse(color: AppPalette.green)
                        .frame(width: 62, height: 62)
                    MascotMicrophoneMark(size: 66)
                }
                .offset(x: 23, y: 5)
            }
            .frame(width: 124, height: 62)
            .offset(x: 56)
        }
        .frame(width: 326, height: 74)
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }

    private var cancelledVoiceTooltip: some View {
        Text(C.t("voiceCapture.cancelled"))
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(height: 48)
            .background(AppPalette.ink)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
            .accessibilityAddTraits(.isStaticText)
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
                .ignoresSafeArea(.container)

            EditableTextPanel(
                text: reviewTextBinding,
                date: nil,
                isHidden: false,
                onToggleHidden: nil,
                onDelete: nil,
                onClose: voiceCapture.cancelReview,
                onRetry: restartVoiceCapture,
                onConfirm: { voiceCapture.saveReviewedVoiceRecord(modelContext: modelContext) }
            )
            .padding(.horizontal, 15)
            .padding(.bottom, 0)
        }
        .ignoresSafeArea(.container, edges: .bottom)
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

    private func startVoiceCapture() {
        cancelNoticeTask?.cancel()
        isCancelNoticeVisible = false
        hasSeenVoiceCaptureCoachmark = true
        Task { await voiceCapture.startRecording() }
    }

    private func cancelVoiceCapture() {
        voiceCapture.cancelRecording()
        cancelNoticeTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) {
            isCancelNoticeVisible = true
        }
        cancelNoticeTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.18)) {
                    isCancelNoticeVisible = false
                }
            }
        }
    }

    private func restartVoiceCapture() {
        voiceCapture.cancelReview()
        Task { await voiceCapture.startRecording() }
    }

    private func openProfile() {
        voiceCapture.handleVoiceSurfaceDismissed()
        selection = .profile
    }
}

private struct VoicePowerWaveform: View {
    let date: Date
    let level: Double
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<24, id: \.self) { index in
                let phase = date.timeIntervalSinceReferenceDate * 4 + Double(index) * 0.58
                let floor = 8.0 + abs(sin(phase)) * 4.0
                let response = min(1, max(0, level)) * (index.isMultiple(of: 5) ? 25.0 : 18.0)
                let height = floor + response * (0.48 + 0.52 * abs(sin(phase)))
                Capsule()
                    .fill(color)
                    .frame(width: 5, height: CGFloat(height))
            }
        }
        .shadow(color: color.opacity(0.45), radius: 5)
    }
}

private struct MascotMicrophoneMark: View {
    let size: CGFloat

    var body: some View {
        Image("MascotOnAir")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

private struct DockVoiceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct EnergyCollectionPulse: View {
    let color: Color

    var body: some View {
        TimelineView(.animation) { context in
            let duration = 1.2
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: duration) / duration

            Circle()
                .stroke(color.opacity(0.42 * (1 - phase)), lineWidth: 2)
                .scaleEffect(0.64 + phase * 0.42)
        }
        .accessibilityHidden(true)
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
