import SwiftUI

/// 零数据/少数据用户在规律页看到的引导壳子。
/// 产品哲学：不是"等你接数据"的空状态，而是"第一天就互动"——Robo 直接抛问题。
/// 消费 EngineOutput.progress（[AccrualProgress]），接线由总管在 InsightsView 完成。
struct OnboardingGuidanceView: View {
    let progress: [AccrualProgress]
    var onTalk: (String) -> Void = { _ in }
    var onConnectHealth: () -> Void = {}
    var onImportDiary: () -> Void = {}

    /// 问题键轮换列表（问题文案走 copy JSON，换问题不动代码）
    private static let questionKeys = [
        "onboarding.q.sleep_onset",
        "onboarding.q.sleep_streak",
        "onboarding.q.cycle",
        "onboarding.q.intraday",
        "onboarding.q.weekday",
        "onboarding.q.daylight",
        "onboarding.q.evening"
    ]

    @State private var questionIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            roboQuestionCard
            sideEntries
            if !progress.isEmpty {
                progressCard
            }
            footer
        }
    }

    // MARK: - 1. Robo 问题卡（主角）

    private var roboQuestionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Circle()
                    .fill(AppPalette.blue)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Text("🤖").font(.system(size: 28))
                    }
                Text(C.t("onboarding.robo.name"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppPalette.ink)
                Spacer(minLength: 0)
            }

            // Robo 先自我介绍（陌生 IP 不许开口就查户口——Ginger 0829）
            Text(C.t("onboarding.intro"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppPalette.muted)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(C.t(Self.questionKeys[questionIndex]))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppPalette.ink)
                .lineSpacing(5)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button {
                    onTalk(Self.questionKeys[questionIndex])
                } label: {
                    Text(C.t("onboarding.answer.talk"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(AppPalette.ink)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        questionIndex = (questionIndex + 1) % Self.questionKeys.count
                    }
                } label: {
                    Text(C.t("onboarding.answer.skip"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppPalette.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .overlay(Capsule().stroke(AppPalette.faint, lineWidth: 1.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(20).background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
    }

    // MARK: - 2. 两个旁路小入口（次要视觉）

    private var sideEntries: some View {
        HStack(spacing: 12) {
            sideEntryCard(
                titleKey: "onboarding.connect.title",
                subKey: "onboarding.connect.sub",
                action: onConnectHealth
            )
            sideEntryCard(
                titleKey: "onboarding.diary.title",
                subKey: "onboarding.diary.sub",
                action: onImportDiary
            )
        }
    }

    private func sideEntryCard(titleKey: String, subKey: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(C.t(titleKey))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppPalette.ink)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                Text(C.t(subKey))
                    .font(.system(size: 12))
                    .foregroundStyle(AppPalette.muted)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .padding(20).background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 3. 进度卡（仅当 progress 非空时显示）

    @ViewBuilder private var progressCard: some View {
        // 只显示"结构性缺件"（周期要记满经期、哨兵要建基线）；天数型配方不显示倒计时——
        // "再攒X天更准"对任何天数都成立，是废话（Ginger 0829）。
        let structural = progress.filter { $0.recipeId == "cyclePhase" || $0.recipeId == "sentinel" }
        if let nearest = structural.min(by: { $0.estimatedCalendarDaysLeft < $1.estimatedCalendarDaysLeft }) {
            VStack(alignment: .leading, spacing: 12) {
                Text(EngineInsightsView.fill(
                    C.t(EvidenceTemplateCatalog.progressCopyKey(recipeId: nearest.recipeId)),
                    ["effectiveDays": "\(nearest.effectiveDays)",
                     "requiredDays": "\(nearest.requiredDays)",
                     "daysLeft": "\(nearest.estimatedCalendarDaysLeft)"]))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppPalette.ink)
                .lineSpacing(4)

                progressBar(ratio: barRatio(nearest))

                if structural.count > 1 {
                    Text(fill(C.t("onboarding.progress.more"), [
                        "{n}": "\(structural.count - 1)"
                    ]))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppPalette.faint)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20).background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
        }
    }

    private func progressBar(ratio: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(AppPalette.background)
                Capsule().fill(AppPalette.green)
                    .frame(width: max(8, geometry.size.width * ratio))
            }
        }
        .frame(height: 8)
    }

    private func barRatio(_ item: AccrualProgress) -> Double {
        guard item.requiredDays > 0 else { return 0 }
        return min(1, max(0, Double(item.effectiveDays) / Double(item.requiredDays)))
    }

    // MARK: - 4. 页尾轻语

    private var footer: some View {
        Text(C.t("onboarding.footer"))
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AppPalette.faint)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
    }

    // MARK: - 槽位填充

    private func fill(_ template: String, _ slots: [String: String]) -> String {
        slots.reduce(template) { result, slot in
            result.replacingOccurrences(of: slot.key, with: slot.value)
        }
    }
}

#Preview("有进度") {
    ScrollView {
        OnboardingGuidanceView(
            progress: [
                AccrualProgress(recipeId: "sleepOnset", effectiveDays: 9,
                                requiredDays: 14, estimatedCalendarDaysLeft: 6),
                AccrualProgress(recipeId: "cyclePhase", effectiveDays: 12,
                                requiredDays: 56, estimatedCalendarDaysLeft: 51),
                AccrualProgress(recipeId: "weekday", effectiveDays: 9,
                                requiredDays: 21, estimatedCalendarDaysLeft: 14)
            ]
        )
        .padding(.horizontal, 16)
    }
    .background(AppPalette.background)
}

#Preview("零数据") {
    ScrollView {
        OnboardingGuidanceView(progress: [])
            .padding(.horizontal, 16)
    }
    .background(AppPalette.background)
}
