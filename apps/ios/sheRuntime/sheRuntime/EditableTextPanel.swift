import SwiftUI

struct EditableTextPanel: View {
    @Binding var text: String
    let date: Date?
    let isHidden: Bool
    let onToggleHidden: (() -> Void)?
    let onDelete: (() -> Void)?
    let onClose: () -> Void
    let onRetry: (() -> Void)?
    let onConfirm: () -> Void
    @FocusState private var isFocused: Bool

    private var isVoiceReview: Bool { date == nil }

    private var isConfirmDisabled: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var estimatedVoiceReviewLineCount: Int {
        text.split(separator: "\n", omittingEmptySubsequences: false).reduce(0) { total, paragraph in
            total + max(1, Int(ceil(Double(paragraph.count) / 13.0)))
        }
    }

    private var voiceReviewEditorHeight: CGFloat {
        let visibleLines = min(9, max(2, estimatedVoiceReviewLineCount))
        return min(252, CGFloat(visibleLines) * 28 + 16)
    }

    private var voiceReviewFontSize: CGFloat {
        estimatedVoiceReviewLineCount > 6 ? 22 : 26
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            if isVoiceReview {
                TextEditor(text: $text)
                    .focused($isFocused)
                    .font(.system(size: voiceReviewFontSize, weight: .semibold, design: .serif))
                    .foregroundStyle(AppPalette.ink)
                    .scrollContentBackground(.hidden)
                    .contentMargins(.vertical, 6, for: .scrollContent)
                    .scrollIndicators(estimatedVoiceReviewLineCount > 9 ? .visible : .hidden)
                    .frame(height: voiceReviewEditorHeight)
                    .accessibilityLabel(C.t("voiceReview.editorAccessibility"))
            } else {
                TextEditor(text: $text)
                    .focused($isFocused)
                    .font(.system(size: 19, weight: .semibold, design: .serif))
                    .foregroundStyle(AppPalette.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 250, idealHeight: 300, maxHeight: 360)
            }

            if let onDelete, let onToggleHidden {
                HStack {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 54, height: 46)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)

                    Spacer()

                    HStack(spacing: 8) {
                        Button(action: onToggleHidden) {
                            Image(systemName: isHidden ? "eye" : "eye.slash")
                                .frame(width: 48, height: 46)
                        }
                        Button(action: onConfirm) {
                            Image(systemName: "square.and.pencil")
                                .frame(width: 48, height: 46)
                        }
                    }
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(AppPalette.ink)
                }
            } else if let onRetry {
                HStack(spacing: 12) {
                    Button(action: retry) {
                        Text(C.t("voiceReview.retry"))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(AppPalette.ink)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(AppPalette.background)
                            .clipShape(Capsule())
                    }

                    Button(action: confirm) {
                        Text(C.t("voiceReview.confirm"))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(AppPalette.green)
                            .clipShape(Capsule())
                    }
                    .disabled(isConfirmDisabled)
                    .opacity(isConfirmDisabled ? 0.42 : 1)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: confirm) {
                    Text(C.t("voiceReview.confirm"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(AppPalette.green)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isConfirmDisabled)
                .opacity(isConfirmDisabled ? 0.42 : 1)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 30)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
        .onAppear {
            isFocused = true
        }
    }

    @ViewBuilder private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            if isVoiceReview {
                Image("MascotDance")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 64)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(C.t("voiceReview.titleName"))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text(C.t("voiceReview.titleMessage"))
                            .font(.system(size: 20, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(AppPalette.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)
                    .accessibilityElement(children: .combine)

                    Text(C.t("voiceReview.subtitle"))
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppPalette.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.top, 2)
            } else if let date {
                Text(date.formatted(.dateTime.year().month().day().hour().minute()))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
            }

            Spacer(minLength: 8)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppPalette.muted)
                    .frame(width: 44, height: 44)
                    .background(AppPalette.background)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func close() {
        isFocused = false
        onClose()
    }

    private func confirm() {
        guard !isConfirmDisabled else { return }
        isFocused = false
        onConfirm()
    }

    private func retry() {
        isFocused = false
        onRetry?()
    }
}
