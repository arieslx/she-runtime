import SwiftUI

struct EditableTextPanel: View {
    @Binding var text: String
    let date: Date?
    let isHidden: Bool
    let onToggleHidden: (() -> Void)?
    let onDelete: (() -> Void)?
    let onClose: () -> Void
    let onConfirm: () -> Void
    @FocusState private var isFocused: Bool

    private var isVoiceReview: Bool { date == nil }

    private var isConfirmDisabled: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            TextEditor(text: $text)
                .focused($isFocused)
                .font(.system(size: date == nil ? 26 : 19, weight: .semibold, design: .serif))
                .foregroundStyle(AppPalette.ink)
                .scrollContentBackground(.hidden)
                .frame(
                    minHeight: isVoiceReview ? 128 : 250,
                    idealHeight: isVoiceReview ? 128 : 300,
                    maxHeight: isVoiceReview ? 128 : 360
                )

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
}
