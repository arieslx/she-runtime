//
//  InsightsView.swift
//  sheRuntime
//
//  洞察页（AI 分析你的规律）。静态页面 + 假数据。
//  照产品原型 她律原型01.html 的 Insights 页。
//

import SwiftUI

struct InsightsView: View {
    private let bg = Color(red: 0.957, green: 0.957, blue: 0.937)

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(C.t("insights.eyebrow")).font(.caption2).fontWeight(.bold)
                        .foregroundStyle(.secondary).tracking(1.5)
                    Text(C.t("insights.title")).font(.system(size: 34, weight: .bold))
                    Text(C.t("insights.subtitle")).font(.footnote).foregroundStyle(.secondary)

                    ForEach(InsightMock.insights) { insight in
                        card(insight)
                    }

                    Text(C.t("insights.footer"))
                        .font(.caption2).foregroundStyle(.tertiary)
                        .padding(.top, 4)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
        }
    }

    private func card(_ i: Insight) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(i.type.uppercased()).font(.caption2).fontWeight(.bold)
                    .foregroundStyle(.secondary).tracking(1)
                Spacer()
                Text(i.count).font(.caption2)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .background(Color(red: 0.925, green: 0.925, blue: 0.898))
                    .clipShape(Capsule())
            }

            Text(i.title).font(.title3).fontWeight(.semibold)
                .padding(.top, 14)
            Text(i.body).font(.footnote).foregroundStyle(.secondary)
                .padding(.top, 8)

            if let impact = i.impact {
                Divider().padding(.vertical, 14)
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(C.t("insights.impactLabel")).font(.caption2).foregroundStyle(.secondary)
                        Text(impact).font(.title2).fontWeight(.bold)
                    }
                    Spacer()
                    if let c = i.confidence {
                        Text(c).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

#Preview { InsightsView() }
