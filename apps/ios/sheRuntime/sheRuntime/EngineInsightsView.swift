// EngineInsightsView.swift — 引擎输出的渲染层（总管接线）
// 三区渲染 EngineOutput：我的规律(established) / 还在观察的线索(observing) / 我猜猜看(guess)
// 视觉照抄 InsightsView 卡片样式：白底、圆角27连续曲率、padding 20、AppPalette 色板

import SwiftUI

struct EngineInsightsView: View {
    let output: EngineOutput
    var onAsk: (String) -> Void = { _ in } // askKey → 跳问问页预填

    @State private var expandedIDs: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let established = output.insights.filter { $0.tier == .established }
            let observing = output.insights.filter { $0.tier == .observing }
            let guesses = output.insights.filter { $0.tier == .guess }

            if !output.subjectiveAlignments.isEmpty {
                subjectiveSection(output.subjectiveAlignments)
                    .padding(.top, 18)
            }
            if !established.isEmpty {
                section(C.t("insights.section.established"), items: established)
                    .padding(.top, output.subjectiveAlignments.isEmpty ? 18 : 28)
            }
            if !observing.isEmpty {
                section(C.t("insights.section.observing"), items: observing)
                    .padding(.top, 28)
            }
            if !guesses.isEmpty {
                section(C.t("insights.section.guess"), items: guesses)
                    .padding(.top, 28)
            }
            if !output.progress.isEmpty {
                progressSection(output.progress).padding(.top, 28)
            }
        }
    }

    // MARK: 区块

    private func subjectiveSection(_ items: [SubjectiveObjectiveAlignment]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(C.t("insights.subjective.sectionTitle"))
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(AppPalette.ink)
            ForEach(items) { alignment in
                subjectiveCard(alignment)
            }
        }
    }

    private func subjectiveCard(_ alignment: SubjectiveObjectiveAlignment) -> some View {
        let isExpanded = expandedIDs.contains(alignment.id)
        let statusKey = alignment.claim == .cooccurrence
            ? "insights.subjective.cooccurrence"
            : "insights.subjective.factOnly"

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    if isExpanded { expandedIDs.remove(alignment.id) } else { expandedIDs.insert(alignment.id) }
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("“\(alignment.userText)”")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppPalette.ink)
                            .lineSpacing(5)
                        Text(C.t(statusKey))
                            .font(.system(size: 13))
                            .foregroundStyle(AppPalette.muted)
                            .lineSpacing(4)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppPalette.faint)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .padding(.top, 7)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(Self.fill(
                    C.t("insights.subjective.trace"),
                    ["time": formattedDate(alignment.occurredAt), "source": sourceLabel(alignment.source)]
                ))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppPalette.faint)
                .padding(.top, 14)

                if alignment.extractionStatus != .completed {
                    Text(C.t("insights.subjective.extractionPending"))
                        .font(.system(size: 12))
                        .foregroundStyle(AppPalette.faint)
                        .padding(.top, 8)
                }

                if !alignment.objectiveFacts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(C.t("insights.subjective.objectiveTitle"))
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.1)
                            .foregroundStyle(AppPalette.faint)
                        ForEach(alignment.objectiveFacts) { fact in
                            HStack(alignment: .firstTextBaseline) {
                                Text(C.t("insights.subjective.metric.\(fact.metricKey)"))
                                Spacer(minLength: 12)
                                Text(objectiveValue(fact))
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppPalette.muted)
                        }
                    }
                    .padding(14)
                    .background(AppPalette.background)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 12)
                }

                Text(C.t("insights.subjective.boundary"))
                    .font(.system(size: 11))
                    .foregroundStyle(AppPalette.faint)
                    .lineSpacing(3)
                    .padding(.top, 12)
            }
        }
        .padding(20)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
    }

    private func section(_ title: String, items: [ComputedInsight]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .serif))
                .foregroundStyle(AppPalette.ink)
            ForEach(items) { insight in
                insightCard(insight)
            }
        }
    }

    private func insightCard(_ insight: ComputedInsight) -> some View {
        let isExpanded = expandedIDs.contains(insight.id)
        let l1 = Self.fill(C.t(EvidenceTemplateCatalog.copyKey(
            recipeId: insight.id, directionKey: insight.directionKey, layer: "l1")), insight.slots)
        let l2 = Self.fill(C.t(EvidenceTemplateCatalog.copyKey(
            recipeId: insight.id, directionKey: insight.directionKey, layer: "l2")), insight.slots)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    if isExpanded { expandedIDs.remove(insight.id) } else { expandedIDs.insert(insight.id) }
                }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Text(l1)
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(AppPalette.ink)
                        .lineSpacing(5)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(AppPalette.faint)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0)).padding(.top, 7)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(l2)
                    .font(.system(size: 14, weight: .regular)).foregroundStyle(AppPalette.muted)
                    .lineSpacing(4).padding(.top, 12)
                if let askKey = insight.askKey {
                    Button { onAsk(askKey) } label: {
                        Text(Self.fill(C.t(askKey), insight.slots))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 9)
                            .background(AppPalette.ink)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain).padding(.top, 12)
                }
            }
        }
        .padding(20).background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
    }

    private func progressSection(_ progress: [AccrualProgress]) -> some View {
        // 只有"结构性缺件"配唯一进度条（周期要记满经期次数、哨兵要建基线尺子）；
        // 天数型配方不显示倒计时——攒几天都"更准"是废话（Ginger 0829），
        // 它们由引擎的三档阶梯自然开口（guess/observing 卡片），不在这里占位。
        let structural = progress.filter { $0.recipeId == "cyclePhase" || $0.recipeId == "sentinel" }
        return VStack(alignment: .leading, spacing: 12) {
            if !structural.isEmpty {
                Text(C.t("insights.section.progress"))
                    .font(.system(size: 22, weight: .bold, design: .serif))
                    .foregroundStyle(AppPalette.ink)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(structural, id: \.recipeId) { p in
                        let text = Self.fill(
                            C.t(EvidenceTemplateCatalog.progressCopyKey(recipeId: p.recipeId)),
                            ["effectiveDays": "\(p.effectiveDays)",
                             "requiredDays": "\(p.requiredDays)",
                             "daysLeft": "\(p.estimatedCalendarDaysLeft)"])
                        VStack(alignment: .leading, spacing: 8) {
                            Text(text)
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(AppPalette.muted)
                                .lineSpacing(4)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(AppPalette.background).frame(height: 8)
                                    Capsule().fill(AppPalette.green)
                                        .frame(width: geo.size.width * min(CGFloat(p.effectiveDays) / CGFloat(max(p.requiredDays, 1)), 1), height: 8)
                                }
                            }
                            .frame(height: 8)
                        }
                    }
                }
                .padding(20).background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: AppLanguage.current == .en ? "en_US" : "zh_CN")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case SubjectiveEventSource.iPhoneVoice.rawValue:
            return C.t("insights.subjective.source.iphoneVoice")
        case SubjectiveEventSource.stopWatchVoice.rawValue:
            return C.t("insights.subjective.source.stopWatch")
        case SubjectiveEventSource.ask.rawValue:
            return C.t("insights.subjective.source.ask")
        case SubjectiveEventSource.onboarding.rawValue:
            return C.t("insights.subjective.source.onboarding")
        default:
            return C.t("insights.subjective.source.legacy")
        }
    }

    private func objectiveValue(_ fact: ObjectiveEvidenceFact) -> String {
        if fact.unitKey == "present" {
            return C.t("insights.subjective.unit.present")
        }
        let value = fact.value.rounded() == fact.value
            ? String(format: "%.0f", fact.value)
            : String(format: "%.1f", fact.value)
        return "\(value) \(C.t("insights.subjective.unit.\(fact.unitKey)"))"
    }

    // MARK: 槽位填充

    /// {slot} 字面替换；weekday 的 lowWeekdayIndex 特殊翻译成周几名
    static func fill(_ template: String, _ slots: [String: String]) -> String {
        var out = template
        for (k, v) in slots {
            if k == "lowWeekdayIndex", let idx = Int(v), (0..<7).contains(idx) {
                out = out.replacingOccurrences(of: "{lowWeekdayName}", with: C.t("weekdays.d\(idx)"))
            }
            out = out.replacingOccurrences(of: "{\(k)}", with: v)
        }
        return out
    }
}
