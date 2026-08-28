import SwiftUI

struct InsightsView: View {
    private let onProfile: () -> Void
    private let evidence: EvidenceDocument?
    private let startsExpanded: Bool

    @State private var expandedRuleIDs: Set<String>
    @State private var expandedAlertIDs: Set<String>
    @State private var isStoryExpanded: Bool
    @State private var isObservingExpanded: Bool

    /// 演示模式（路演专用，ProfileView 开关）：开 = 渲染打包的 evidence_zh.json
    @AppStorage("demo_mode_enabled") private var demoModeEnabled = false
    /// 主路径：引擎用她自己的数据当场算出的结果
    @State private var engineOutput: EngineOutput?
    @State private var isComputing = true

    init(onProfile: @escaping () -> Void = {}) {
        let loaded = EvidenceLibrary.load()
        let expanded = ProcessInfo.processInfo.environment["INSIGHTS_EXPANDED"] == "1"
        self.onProfile = onProfile
        evidence = loaded
        startsExpanded = expanded
        _expandedRuleIDs = State(initialValue: expanded ? Set(loaded?.rules.map(\.id) ?? []) : [])
        _expandedAlertIDs = State(initialValue: expanded ? Set(loaded?.alerts.items.map(\.id) ?? []) : [])
        _isStoryExpanded = State(initialValue: expanded)
        _isObservingExpanded = State(initialValue: expanded)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if !startsExpanded {
                        brandHeader
                        Text(C.t("insights.pageTitle"))
                            .font(.system(size: 38, weight: .bold, design: .serif))
                            .foregroundStyle(AppPalette.ink).padding(.top, 10)
                    }

                    if demoModeEnabled {
                        // ③演示模式（路演专用）：渲染打包的示例数据，说明"这是真实用户数据跑出的例子"
                        if let evidence {
                            if !startsExpanded {
                                nowCard(evidence.nowCard) { openRule(evidence.nowCard.linkRule, proxy: proxy) }
                                    .padding(.top, 18)
                            }
                            rulesSection(evidence.rules, proxy: proxy).padding(.top, 28)
                            alertsSection(evidence.alerts, proxy: proxy).padding(.top, 28)
                            tipsSection(evidence.tips, proxy: proxy).padding(.top, 28)
                            storySection(evidence.storyCard).padding(.top, 28)
                            observingSection(evidence.observing).padding(.top, 28)
                        }
                    } else if let output = engineOutput, output.hasAnyData {
                        // ①主路径：她自己的数据、当场算出的规律
                        EngineInsightsView(output: output)
                    } else if !isComputing {
                        // ②零数据新用户：Robo 直接开聊 + 旁路入口 + 进度
                        OnboardingGuidanceView(
                            progress: engineOutput?.progress ?? [],
                            onConnectHealth: { Task { await connectHealthAndRecompute() } }
                        )
                        .padding(.top, 18)
                    }
                    Spacer(minLength: 120)
                }
                .padding(.horizontal, 16).padding(.top, 8)
            }
        }
        .background(AppPalette.background)
        .task { await recompute() }
    }

    // MARK: 引擎接线（三根线的取数逻辑）

    private func recompute() async {
        isComputing = true
        defer { isComputing = false }
        let store = HealthDataStore.shared
        do {
            try await store.sync()
        } catch {
            // 无授权/同步失败不是错误态：继续用库里已有的（可能为空）数据算
        }
        do {
            let daily = try await store.dailyRecords()
            let hourly = try await store.hourlyRecords()
            let notes = await store.subjectiveNotes
            let rate = (try? await store.recentAccrualRate()) ?? 0
            let engine = EvidenceEngine(accrualRate: rate)
            engineOutput = engine.compute(daily: daily, hourly: hourly, notes: notes)
        } catch {
            engineOutput = EngineOutput(insights: [], progress: [], hasAnyData: false)
        }
    }

    private func connectHealthAndRecompute() async {
        try? await HealthDataAuthService().requestFullAuthorization()
        await recompute()
    }

    private var brandHeader: some View {
        HStack {
            Image("AppLogo").resizable().scaledToFit().frame(width: 91, height: 50, alignment: .leading)
            Spacer()
            ProfileMenuButton(action: onProfile)
        }
    }

    private func nowCard(_ card: EvidenceNowCard, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 14) {
                    eyebrow(C.t("insights.now.title"), color: AppPalette.green)
                    Text(card.l1)
                        .font(.system(size: 20, weight: .bold)).foregroundStyle(AppPalette.ink)
                        .lineSpacing(5).padding(.trailing, 46)
                    HStack(spacing: 6) {
                        Text(C.t("insights.now.link"))
                        Image(systemName: "arrow.down")
                    }
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(AppPalette.green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image("MascotTier2").resizable().scaledToFit()
                    .frame(width: 72, height: 76).offset(x: 8, y: 8)
            }
            .padding(20).background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func rulesSection(_ rules: [EvidenceRule], proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(C.t("insights.rules.title"))
            ForEach(rules.sorted { $0.priority < $1.priority }) { rule in
                ruleCard(rule, proxy: proxy).id("rule-\(rule.id)")
            }
        }
    }

    private func ruleCard(_ rule: EvidenceRule, proxy: ScrollViewProxy) -> some View {
        let isExpanded = expandedRuleIDs.contains(rule.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { toggle(rule.id, in: &expandedRuleIDs) }
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        eyebrow(C.t("insights.rules.\(rule.id).title"), color: ruleColor(rule.id))
                        Text(rule.l1)
                            .font(.system(size: 17, weight: .semibold)).foregroundStyle(AppPalette.ink)
                            .lineSpacing(5)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(AppPalette.faint)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0)).padding(.top, 7)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().overlay(Color.black.opacity(0.07)).padding(.vertical, 18)
                Text(rule.l2).font(.system(size: 14)).foregroundStyle(AppPalette.muted).lineSpacing(6)
                ruleDetails(rule).padding(.top, 18)
                Text(rule.l4).font(.system(size: 12)).foregroundStyle(AppPalette.faint)
                    .lineSpacing(4).padding(.top, 16)
                if rule.id == "premenstrual" {
                    ruleExit(C.t("insights.rules.premenstrual.exit")) { proxy.scrollTo("alerts", anchor: .top) }
                } else if rule.id == "sleep3days" {
                    ruleExit(C.t("insights.rules.sleep3days.exit")) { proxy.scrollTo("tips", anchor: .top) }
                }
            }
        }
        .padding(20).background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
    }

    @ViewBuilder private func ruleDetails(_ rule: EvidenceRule) -> some View {
        if let hrv = rule.l3.phaseHRV, let rhr = rule.l3.phaseRHR {
            VStack(alignment: .leading, spacing: 16) {
                metricChart(C.t("insights.details.sleepRepair"), values: phaseValues(hrv))
                metricChart(C.t("insights.details.heartRateRecovery"), values: phaseValues(rhr))
                if let count = rule.l3.cycleCount {
                    caption(String(format: C.t("insights.details.cycleCountFormat"), count))
                }
            }
        } else if let rested = rule.l3.restedRHR, let short = rule.l3.shortRHR {
            VStack(alignment: .leading, spacing: 12) {
                metricChart(C.t("insights.details.standbyUse"), values: [
                    (C.t("insights.details.threeDaysEnough"), rested),
                    (C.t("insights.details.notEnough"), short)
                ])
            }
        } else if let onset = rule.l3.hrvByOnset, let ratio = rule.l3.enoughRatio {
            VStack(alignment: .leading, spacing: 16) {
                metricChart(C.t("insights.details.sleepOnsetSlope"), values: [
                    (C.t("insights.details.beforeMidnight"), onset.beforeMidnight),
                    (C.t("insights.details.oneToThree"), onset.oneToThree),
                    (C.t("insights.details.afterThree"), onset.afterThree)
                ])
                metricChart(C.t("insights.details.enoughSleepChance"), values: [
                    (C.t("insights.details.beforeMidnight"), ratio.beforeMidnight * 100),
                    (C.t("insights.details.afterThree"), ratio.afterThree * 100)
                ], suffix: "%")
            }
        }
    }

    private func phaseValues(_ values: EvidencePhaseValues) -> [(String, Double)] {
        [(C.t("insights.details.usualYou"), values.other),
         (C.t("insights.details.beforePeriod"), values.premenstrual),
         (C.t("insights.details.duringPeriod"), values.menses)]
    }

    private func alertsSection(_ alerts: EvidenceAlerts, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(C.t("insights.alerts.sectionTitle"))
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom) {
                    Text(C.t(alerts.titleKey))
                        .font(.system(size: 22, weight: .bold, design: .serif)).foregroundStyle(AppPalette.ink)
                    Spacer()
                    Image("MascotTier1").resizable().scaledToFit().frame(width: 58, height: 64)
                }
                ForEach(Array(alerts.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(Color.black.opacity(0.07)) }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Button {
                                guard let ruleID = item.linkRule else { return }
                                openRule(ruleID, proxy: proxy)
                            } label: {
                                Text(item.text).font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppPalette.ink).frame(maxWidth: .infinity, alignment: .leading)
                                    .multilineTextAlignment(.leading)
                            }
                            .buttonStyle(.plain).disabled(item.linkRule == nil)
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { toggle(item.id, in: &expandedAlertIDs) }
                            } label: {
                                Image(systemName: "umbrella.fill").font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(AppPalette.blue).frame(width: 34, height: 34)
                                    .background(AppPalette.blue.opacity(0.16)).clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(C.t("insights.alerts.umbrellaAccessibility"))
                        }
                        if expandedAlertIDs.contains(item.id) {
                            Text(item.umbrella).font(.system(size: 12, weight: .medium))
                                .foregroundStyle(AppPalette.muted).lineSpacing(4).padding(.trailing, 38)
                        }
                    }
                    .padding(.vertical, 13)
                }
            }
            .padding(20).background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
        }
        .id("alerts")
    }

    private func tipsSection(_ tips: EvidenceTips, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(C.t("insights.tips.sectionTitle"))
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(C.t(tips.titleKey)).font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundStyle(AppPalette.ink).padding(.trailing, 52)
                    // rank 1,2,… 按名次升序；rank 0（诚实边界）永远垫底
                    ForEach(Array(tips.items.sorted { ($0.rank == 0 ? Int.max : $0.rank) < ($1.rank == 0 ? Int.max : $1.rank) }.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider().overlay(Color.black.opacity(0.07)).padding(.vertical, 14) }
                        Button {
                            guard let ruleID = item.linkRule else { return }
                            openRule(ruleID, proxy: proxy)
                        } label: {
                            Text(item.text)
                                .font(.system(size: item.rank == 1 ? 18 : 14, weight: item.rank == 1 ? .bold : .regular))
                                .foregroundStyle(item.rank == 0 ? AppPalette.faint : AppPalette.ink).lineSpacing(5)
                                .frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain).disabled(item.linkRule == nil)
                    }
                }
                Image("MascotTier4").resizable().scaledToFit()
                    .frame(width: 70, height: 76).offset(x: 10, y: 10)
            }
            .padding(20).background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
        }
        .id("tips")
    }

    private func storySection(_ story: EvidenceStoryCard) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(C.t("insights.story.sectionTitle"))
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) { isStoryExpanded.toggle() }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Text(story.l1).font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppPalette.ink).lineSpacing(5)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppPalette.faint)
                            .rotationEffect(.degrees(isStoryExpanded ? 180 : 0)).padding(.top, 6)
                    }
                }
                .buttonStyle(.plain)
                if isStoryExpanded {
                    Divider().overlay(Color.black.opacity(0.07)).padding(.vertical, 18)
                    storyChart(story.details)
                    Text(C.t("insights.story.placeholder")).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppPalette.faint).frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 14)
                }
            }
            .padding(20).background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
        }
    }

    private func observingSection(_ observations: [EvidenceObservation]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { isObservingExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    sectionTitle(C.t("insights.observing.title"))
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
                        .foregroundStyle(AppPalette.faint)
                        .rotationEffect(.degrees(isObservingExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isObservingExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(observations.enumerated()), id: \.element.id) { index, observation in
                        if index > 0 { Divider().overlay(Color.black.opacity(0.07)) }
                        Text(observation.text).font(.system(size: 14)).foregroundStyle(AppPalette.muted)
                            .lineSpacing(6).padding(.vertical, 16)
                    }
                }
                .padding(.horizontal, 20).background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
            }
        }
    }

    private func metricChart(_ title: String, values: [(String, Double)], suffix: String = "") -> some View {
        let maximum = max(values.map(\.1).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(AppPalette.faint)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, item in
                    VStack(spacing: 6) {
                        Text("\(formatted(item.1))\(suffix)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppPalette.ink)
                        Capsule().fill(AppPalette.green.opacity(0.72))
                            .frame(height: max(18, 70 * item.1 / maximum))
                        Text(item.0).font(.system(size: 10, weight: .medium)).foregroundStyle(AppPalette.muted)
                            .lineLimit(2).multilineTextAlignment(.center).frame(height: 28, alignment: .top)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 130, alignment: .bottom).padding(12).background(AppPalette.background)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func storyChart(_ details: EvidenceStoryDetails) -> some View {
        let values = (0..<24).compactMap { details.hourlySeatedHR[String($0)] }
        return VStack(alignment: .leading, spacing: 10) {
            Text(C.t("insights.story.chartTitle")).font(.system(size: 11, weight: .bold))
                .foregroundStyle(AppPalette.faint)
            InsightLineChart(values: values)
                .stroke(AppPalette.green, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .frame(height: 128).background(AppPalette.background)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func ruleExit(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) { Text(title); Image(systemName: "arrow.down") }
                .font(.system(size: 12, weight: .bold)).foregroundStyle(AppPalette.green)
        }
        .buttonStyle(.plain).padding(.top, 16)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 22, weight: .bold, design: .serif)).foregroundStyle(AppPalette.ink)
    }

    private func eyebrow(_ title: String, color: Color) -> some View {
        Text(title).font(.system(size: 10, weight: .bold)).tracking(1.1).foregroundStyle(.white)
            .padding(.horizontal, 12).frame(height: 28).background(color).clipShape(Capsule())
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(AppPalette.faint)
    }

    private func ruleColor(_ id: String) -> Color {
        id == "premenstrual" ? AppPalette.blue : (id == "sleep3days" ? AppPalette.green : AppPalette.ink)
    }

    private func openRule(_ id: String, proxy: ScrollViewProxy) {
        expandedRuleIDs.insert(id)
        withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo("rule-\(id)", anchor: .top) }
    }

    private func toggle(_ id: String, in set: inout Set<String>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func formatted(_ value: Double) -> String {
        value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}

private struct InsightLineChart: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        guard values.count > 1, let minimum = values.min(), let maximum = values.max() else { return Path() }
        let range = max(maximum - minimum, 1)
        let plot = rect.insetBy(dx: 14, dy: 14)
        var path = Path()
        for (index, value) in values.enumerated() {
            let x = plot.minX + plot.width * CGFloat(index) / CGFloat(values.count - 1)
            let y = plot.maxY - plot.height * CGFloat((value - minimum) / range)
            index == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
        }
        return path
    }
}

#Preview { InsightsView() }
