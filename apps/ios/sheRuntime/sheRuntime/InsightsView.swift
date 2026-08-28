import SwiftUI

struct InsightsView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                brandHeader.padding(.bottom, 18)

                Text(C.t("insights.eyebrow"))
                    .font(.system(size: 11, weight: .bold)).tracking(2.3)
                    .foregroundStyle(AppPalette.faint)
                Text(C.t("insights.titleNative"))
                    .font(.system(size: 38, weight: .bold, design: .serif))
                    .foregroundStyle(AppPalette.ink).padding(.top, 5)
                Text(C.t("insights.subtitleShort"))
                    .font(.system(size: 14)).foregroundStyle(AppPalette.muted).padding(.top, 7)

                primaryCard.padding(.top, 18)
                boosterCard.padding(.top, 12)
                newPatternCard.padding(.top, 12)

                Button(C.t("insights.more")) { }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(.white).clipShape(Capsule())
                    .padding(.top, 12)

                Spacer(minLength: 120)
            }
            .padding(.horizontal, 16).padding(.top, 8)
        }
        .background(AppPalette.background)
    }

    private var brandHeader: some View {
        HStack {
            Image("AppLogo").resizable().scaledToFit()
                .frame(width: 91, height: 50, alignment: .leading)
            Spacer()
            Button(C.t("today.languageButton")) { }
                .font(.system(size: 15, weight: .bold)).foregroundStyle(AppPalette.ink)
                .frame(width: 45, height: 45).background(.white).clipShape(Circle())
                .shadow(color: .black.opacity(0.035), radius: 12, y: 5)
            Image("ProfileAvatar").resizable().scaledToFill()
                .frame(width: 45, height: 45).clipShape(Circle())
        }
    }

    private var primaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            pill(C.t("insights.drainerLabel"), color: AppPalette.green)
            Text(C.t("insights.drainerTitle"))
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(AppPalette.ink).lineSpacing(3).padding(.top, 18)
            Text(C.t("insights.drainerBody"))
                .font(.system(size: 14)).foregroundStyle(AppPalette.muted)
                .lineSpacing(6).padding(.top, 12)
            Divider().overlay(Color.black.opacity(0.07)).padding(.vertical, 18)
            HStack(spacing: 42) {
                stat(label: C.t("insights.similarDays"), value: "5 / 6")
                stat(label: C.t("insights.window"), value: "14:00–17:00")
            }
        }
        .padding(20).background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
    }

    private var boosterCard: some View {
        ZStack(alignment: .bottomLeading) {
            compactCard(
                tag: C.t("insights.boosterLabel"),
                title: C.t("insights.boosterTitle"),
                body: C.t("insights.boosterBody"),
                color: AppPalette.green,
                leadingInset: 116
            )
            Image("MascotTier4").resizable().scaledToFit()
                .frame(width: 112, height: 126).offset(x: 2, y: 2)
        }
    }

    private var newPatternCard: some View {
        compactCard(
            tag: C.t("insights.newLabel"),
            title: C.t("insights.newTitle"),
            body: C.t("insights.newBody"),
            color: AppPalette.blue,
            leadingInset: 0
        )
    }

    private func compactCard(tag: String, title: String, body: String, color: Color, leadingInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            pill(tag, color: color)
            Text(title).font(.system(size: 18, weight: .bold)).foregroundStyle(AppPalette.ink)
                .lineSpacing(3).padding(.top, 14)
            Text(body).font(.system(size: 13)).foregroundStyle(AppPalette.muted)
                .lineSpacing(5).padding(.top, 8)
        }
        .padding(.leading, 20 + leadingInset).padding(.trailing, 20)
        .padding(.vertical, 20).frame(maxWidth: .infinity, minHeight: 174, alignment: .topLeading)
        .background(.white).clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(.white)
            .padding(.horizontal, 13).frame(height: 29).background(color).clipShape(Capsule())
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 9, weight: .bold)).tracking(1.5)
                .foregroundStyle(AppPalette.faint)
            Text(value).font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundStyle(AppPalette.ink)
        }
    }
}

#Preview { InsightsView() }
