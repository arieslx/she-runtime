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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                if let date {
                    Text(date.formatted(.dateTime.year().month().day().hour().minute()))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppPalette.muted)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppPalette.muted)
                        .frame(width: 42, height: 42)
                        .background(AppPalette.background)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            TextEditor(text: $text)
                .focused($isFocused)
                .font(.system(size: date == nil ? 26 : 19, weight: .semibold, design: .serif))
                .foregroundStyle(AppPalette.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: date == nil ? 180 : 250, maxHeight: 360)

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
                Button(action: onConfirm) {
                    Text(C.t("voiceReview.confirm"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(AppPalette.green)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
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
}
