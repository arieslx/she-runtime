import SwiftUI

struct ProfileMenuButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image("MenuBars")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(AppPalette.ink)
                .frame(width: 25, height: 18)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(C.t("profile.menuAccessibility"))
    }
}
