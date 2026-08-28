import SwiftUI

struct AskView: View {
    @State private var inputText = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    brandHeader.padding(.bottom, 18)
                    Text("ASK YOUR DATA")
                        .font(.system(size: 11, weight: .bold)).tracking(2.3)
                        .foregroundStyle(AppPalette.faint)
                    Text("Ask")
                        .font(.system(size: 38, weight: .bold, design: .serif))
                        .foregroundStyle(AppPalette.ink).padding(.top, 5)
                    Text("查询你自己的数据与长期模式")
                        .font(.system(size: 14)).foregroundStyle(AppPalette.muted).padding(.top, 7)

                    assistantGreeting.padding(.top, 18)
                    userQuestion.padding(.top, 12)
                    answerRow.padding(.top, 12)
                    suggestionButtons.padding(.top, 12)
                }
                .padding(.horizontal, 16).padding(.top, 8)
                .padding(.bottom, 14)
            }

            inputBar.padding(.horizontal, 16).padding(.bottom, 8)
        }
        .background(AppPalette.background)
    }

    private var brandHeader: some View {
        HStack {
            Image("AppLogo").resizable().scaledToFit()
                .frame(width: 91, height: 50, alignment: .leading)
            Spacer()
            Button("EN") { }
                .font(.system(size: 15, weight: .bold)).foregroundStyle(AppPalette.ink)
                .frame(width: 45, height: 45).background(.white).clipShape(Circle())
                .shadow(color: .black.opacity(0.035), radius: 12, y: 5)
            Image("ProfileAvatar").resizable().scaledToFill()
                .frame(width: 45, height: 45).clipShape(Circle())
        }
    }

    private var assistantGreeting: some View {
        HStack(alignment: .bottom, spacing: 7) {
            mascot
            Text("想了解什么？可以直接问我。")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(AppPalette.ink)
                .padding(.horizontal, 17).frame(height: 52)
                .background(.white).clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Spacer(minLength: 24)
        }
    }

    private var userQuestion: some View {
        Text("为什么我今天下午状态掉得这么快？")
            .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
            .padding(.horizontal, 18).frame(minHeight: 54)
            .background(AppPalette.green)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var answerRow: some View {
        HStack(alignment: .top, spacing: 7) {
            mascot.padding(.top, 2)
            VStack(alignment: .leading, spacing: 0) {
                Text("ANSWER · LAST 28 DAYS")
                    .font(.system(size: 10, weight: .bold)).tracking(1.3)
                    .foregroundStyle(Color(red: 91 / 255, green: 125 / 255, blue: 194 / 255))
                Text("今天身体恢复接近基线。下午的下降发生在连续沟通后：13:40–17:10 共 3 场会议，符合你的高消耗模式。")
                    .font(.system(size: 14)).foregroundStyle(AppPalette.ink)
                    .lineSpacing(5).padding(.top, 13)
                HStack(spacing: 8) {
                    summary(label: "TODAY", value: "3 meetings · 152 min")
                    summary(label: "YOUR PATTERN", value: "90+ min → lower")
                }
                .padding(.top, 14)
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
            suggestion("什么最能帮我恢复？")
            suggestion("何时适合深度工作？")
        }
    }

    private func suggestion(_ title: String) -> some View {
        Button { inputText = title } label: {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(AppPalette.muted)
                .lineLimit(1).frame(maxWidth: .infinity, minHeight: 38)
                .background(.white).clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var inputBar: some View {
        HStack(spacing: 9) {
            TextField("Ask about your energy…", text: $inputText)
                .font(.system(size: 14)).foregroundStyle(AppPalette.ink)
                .padding(.leading, 13).submitLabel(.send)
            Button { inputText = "" } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 42, height: 42).background(AppPalette.green).clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(6).frame(height: 56).background(.white).clipShape(Capsule())
        .shadow(color: .black.opacity(0.04), radius: 14, y: 5)
    }
}

#Preview { AskView() }
