//
//  MapView.swift
//  sheRuntime
//
//  地图页（精力地图）。静态页面 + 假数据，文案来自 AppMockData.swift。
//  照产品原型 她律原型01.html 的 Map 页。
//

import SwiftUI

struct MapView: View {
    private let bg = Color(red: 0.957, green: 0.957, blue: 0.937)

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(C.t("map.eyebrow")).font(.caption2).fontWeight(.bold)
                        .foregroundStyle(.secondary).tracking(1.5)
                    Text(C.t("map.title")).font(.system(size: 34, weight: .bold))
                    Text(C.t("map.subtitle")).font(.footnote).foregroundStyle(.secondary)

                    chartCard
                    windowsSection
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                Text(MapMock.rangeText).font(.title3).fontWeight(.semibold)
                Spacer()
                Text(C.t("map.rangeTag")).font(.caption2).foregroundStyle(.secondary)
            }

            EnergyCurve(points: MapMock.curve)
                .frame(height: 200)

            HStack {
                ForEach(MapMock.hourLabels, id: \.self) { h in
                    Text(h).font(.caption2).foregroundStyle(.secondary)
                    if h != MapMock.hourLabels.last { Spacer() }
                }
            }

            HStack(spacing: 16) {
                legendDot(Color(red: 0.66, green: 0.79, blue: 0.55), C.t("map.legendBoost"))
                legendDot(Color(red: 0.83, green: 0.65, blue: 0.61), C.t("map.legendDrain"))
            }
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }

    private func legendDot(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var windowsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(C.t("map.windowsTitle")).font(.subheadline).fontWeight(.semibold)
                Spacer()
                Text(C.t("map.baselineTag")).font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                ForEach(MapMock.windows) { w in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(w.label).font(.caption2).foregroundStyle(.secondary)
                        Text(w.range).font(.headline)
                        Text(w.note).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            }
        }
    }
}

// 精力曲线（把 0~1 的采样点画成平滑折线 + 渐变填充）
struct EnergyCurve: View {
    let points: [Double]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let step = points.count > 1 ? w / CGFloat(points.count - 1) : w

            let path = Path { p in
                for (i, v) in points.enumerated() {
                    let x = CGFloat(i) * step
                    let y = CGFloat(v) * h
                    if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                    else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
            }

            ZStack {
                // 渐变填充
                path.strokedPath(.init(lineWidth: 0)) // 占位
                fillPath(w: w, h: h, step: step)
                    .fill(LinearGradient(
                        colors: [Color.black.opacity(0.12), Color.black.opacity(0)],
                        startPoint: .top, endPoint: .bottom))
                // 线
                path.stroke(.black, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
    }

    private func fillPath(w: CGFloat, h: CGFloat, step: CGFloat) -> Path {
        Path { p in
            for (i, v) in points.enumerated() {
                let x = CGFloat(i) * step
                let y = CGFloat(v) * h
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
                else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
            p.addLine(to: CGPoint(x: w, y: h))
            p.addLine(to: CGPoint(x: 0, y: h))
            p.closeSubpath()
        }
    }
}

#Preview { MapView() }
