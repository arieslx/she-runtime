import SwiftUI

struct AskView: View {
    private let onProfile: () -> Void
    @State private var inputText = ""
    @StateObject private var speechInput = AskSpeechInputViewModel()
    @StateObject private var chat = AskChatViewModel()

    init(onProfile: @escaping () -> Void = {}) { self.onProfile = onProfile }

    private var displayedExchange: AskChatExchange {
        chat.activeExchange ?? AskChatExchange(
            question: C.t("ask.question"),
            response: AskChatResponse(
                answer: C.t("ask.answer"),
                basis: [
                    AskChatBasis(label: C.t("ask.todayLabel"), value: C.t("ask.todayValue")),
                    AskChatBasis(label: C.t("ask.patternLabel"), value: C.t("ask.patternValue"))
                ]
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    brandHeader.padding(.bottom, 18)
                    Text(C.t("ask.eyebrow"))
                        .font(.system(size: 11, weight: .bold)).tracking(2.3)
                        .foregroundStyle(AppPalette.faint)
                    Text(C.t("ask.titleNative"))
                        .font(.system(size: 38, weight: .bold, design: .serif))
                        .foregroundStyle(AppPalette.ink).padding(.top, 5)
                    Text(C.t("ask.subtitleShort"))
                        .font(.system(size: 14)).foregroundStyle(AppPalette.muted).padding(.top, 7)

                    assistantGreeting.padding(.top, 18)
                    userQuestion(displayedExchange.question).padding(.top, 12)
                    answerRow(displayedExchange.response).padding(.top, 12)
                    suggestionButtons.padding(.top, 12)
                }
                .padding(.horizontal, 16).padding(.top, 8)
                .padding(.bottom, 14)
            }

            VStack(spacing: 7) {
                speechStatus
                inputBar
            }
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
        .background(AppPalette.background)
        .onChange(of: speechInput.recognizedText) { _, text in
            inputText = text
        }
    }

    private var brandHeader: some View {
        HStack {
            Image("AppLogo").resizable().scaledToFit()
                .frame(width: 91, height: 50, alignment: .leading)
            Spacer()
            ProfileMenuButton(action: onProfile)
        }
    }

    private var assistantGreeting: some View {
        HStack(alignment: .bottom, spacing: 7) {
            mascot
            Text(C.t("ask.greeting"))
                .font(.system(size: 14, weight: .medium)).foregroundStyle(AppPalette.ink)
                .padding(.horizontal, 17).frame(height: 52)
                .background(.white).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Spacer(minLength: 24)
        }
    }

    private func userQuestion(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
            .padding(.horizontal, 18).frame(minHeight: 54)
            .background(AppPalette.green)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func answerRow(_ response: AskChatResponse?) -> some View {
        HStack(alignment: .top, spacing: 7) {
            mascot.padding(.top, 2)
            VStack(alignment: .leading, spacing: 0) {
                Text(C.t("ask.answerLabel"))
                    .font(.system(size: 10, weight: .bold)).tracking(1.3)
                    .foregroundStyle(Color(red: 91 / 255, green: 125 / 255, blue: 194 / 255))
                Text(response?.answer ?? C.t("ask.loadingAnswer"))
                    .font(.system(size: 14)).foregroundStyle(AppPalette.ink)
                    .lineSpacing(5).padding(.top, 13)
                if let response {
                    HStack(spacing: 8) {
                        ForEach(response.basis) { item in
                            summary(label: item.label, value: item.value)
                        }
                    }
                    .padding(.top, 14)
                    if let safetyNote = response.safetyNote, !safetyNote.isEmpty {
                        Text(safetyNote)
                            .font(.system(size: 11))
                            .foregroundStyle(AppPalette.faint)
                            .lineSpacing(3)
                            .padding(.top, 12)
                    }
                    if let followUp = response.followUp, !followUp.isEmpty {
                        Text(followUp)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppPalette.muted)
                            .lineSpacing(3)
                            .padding(.top, 8)
                    }
                    if let usage = response.usage {
                        Text(String(format: C.t("ask.deepSeekUsageFormat"), usage.deepSeekCallCount))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(AppPalette.faint)
                            .padding(.top, 10)
                    }
                }
            }
            .padding(18).background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var mascot: some View {
        Image("MascotTier3").resizable().scaledToFit().frame(width: 39, height: 42)
    }

    private func summary(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 9, weight: .bold)).tracking(1.1)
                .foregroundStyle(AppPalette.faint)
            Text(value).font(.system(size: 11, weight: .bold)).foregroundStyle(AppPalette.ink)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .padding(.horizontal, 12).background(AppPalette.background)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var suggestionButtons: some View {
        HStack(spacing: 8) {
            suggestion(C.t("ask.suggestionRecovery"))
            suggestion(C.t("ask.suggestionFocus"))
        }
    }

    private func suggestion(_ title: String) -> some View {
        Button {
            speechInput.cancelRecording()
            inputText = title
        } label: {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(AppPalette.muted)
                .lineLimit(1).frame(maxWidth: .infinity, minHeight: 38)
                .background(.white).clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var speechStatus: some View {
        Group {
            if speechInput.isRecording {
                Text(C.t("ask.speechListening"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppPalette.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 18)
            } else if let errorKey = speechInput.errorKey {
                Text(C.t(errorKey))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppPalette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 18)
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 7) {
            TextField(C.t("ask.inputPlaceholderShort"), text: $inputText)
                .font(.system(size: 14)).foregroundStyle(AppPalette.ink)
                .padding(.leading, 13).submitLabel(.send)
                .onSubmit { sendMessage() }
            micButton
            Button { sendMessage() } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 42, height: 42).background(AppPalette.green).clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(C.t("ask.sendAccessibility"))
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isResponding)
            .opacity(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isResponding ? 0.55 : 1)
        }
        .padding(6).frame(height: 56).background(.white).clipShape(Capsule())
        .shadow(color: .black.opacity(0.04), radius: 14, y: 5)
    }

    private var micButton: some View {
        Button {
            Task { await speechInput.toggle(currentText: inputText) }
        } label: {
            ZStack {
                if speechInput.isRecording {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    AppPalette.green.opacity(0.35),
                                    AppPalette.green,
                                    Color(red: 187 / 255, green: 231 / 255, blue: 102 / 255)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 46, height: 46)
                        .shadow(color: AppPalette.green.opacity(0.28), radius: 5)
                }
                Circle()
                    .fill(AppPalette.background)
                    .frame(width: 40, height: 40)
                Image(systemName: speechInput.isRecording ? "mic.fill" : "mic")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(speechInput.isRecording ? AppPalette.green : AppPalette.muted)
            }
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(C.t(speechInput.isRecording ? "ask.speechStopAccessibility" : "ask.speechStartAccessibility"))
    }

    private func sendMessage() {
        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !chat.isResponding else { return }
        speechInput.stopRecording()
        chat.send(message)
        inputText = ""
    }
}

#Preview { AskView() }
