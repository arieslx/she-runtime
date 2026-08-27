//
//  TodayView.swift
//  sheRuntime
//
//  Today 页面（静态页面 + 交互）。
//  所有文字和数字都来自 TodayMockData.swift，这里只负责「长什么样、怎么点」。
//  照产品原型 她律原型01.html 的 Today 页实现。
//

import SwiftUI

struct TodayView: View {
    // 悬浮录音按钮的状态：按住时变化
    @State private var isRecording = false
    @State private var justSaved = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(red: 0.957, green: 0.957, blue: 0.937) // 原型米白底
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    topBar
                    heroCard
                    timelineSection
                    Spacer(minLength: 90) // 给底部悬浮按钮留空间
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }

            voiceButton
                .padding(.bottom, 28)
        }
    }

    // MARK: - 顶部：日期 + 我的头像
    private var topBar: some View {
        HStack {
            Text(C.t("today.dateText").uppercased())
                .font(.caption).fontWeight(.bold)
                .foregroundStyle(.secondary)
                .tracking(1.5)
            Spacer()
            HStack(spacing: 8) {
                Text(C.t("tabs.profile")).font(.caption).fontWeight(.semibold)
                Circle()
                    .fill(.black)
                    .frame(width: 38, height: 38)
                    .overlay(Text(C.t("today.avatarInitial"))
                        .font(.subheadline).fontWeight(.bold)
                        .foregroundStyle(.white))
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - 精力主卡
    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(TodayMock.energyScore)")
                        .font(.system(size: 72, weight: .semibold))
                    Text(C.t("today.energyLabel").uppercased())
                        .font(.caption2).fontWeight(.bold)
                        .foregroundStyle(.secondary).tracking(1.2)
                }
                Spacer()
                Text(C.t("today.stateText"))
                    .font(.caption).fontWeight(.bold)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color(red: 0.874, green: 0.968, blue: 0.776))
                    .clipShape(Capsule())
            }

            Text(C.t("today.heroCopy"))
                .font(.title3).fontWeight(.medium)
                .padding(.top, 22)

            Text(C.t("today.subCopy"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            Text(C.t("today.disclaimer"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 6)

            HStack(spacing: 8) {
                metricBox(C.t("today.metricSleepLabel"), TodayMock.metricSleep)
                metricBox(C.t("today.metricHRVLabel"), TodayMock.metricHRV)
                metricBox(C.t("today.metricRestingHRLabel"), TodayMock.metricRestingHR)
            }
            .padding(.top, 20)
        }
        .padding(24)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    private func metricBox(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(key).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline).fontWeight(.bold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(red: 0.925, green: 0.925, blue: 0.898))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - 时间线
    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(C.t("today.timelineTitle")).font(.subheadline).fontWeight(.semibold)
                Spacer()
                Text("\(TodayMock.events.count) 条")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(Array(TodayMock.events.enumerated()), id: \.element.id) { index, event in
                    eventRow(event, isLast: index == TodayMock.events.count - 1)
                }
            }
            .padding(.horizontal, 16)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .padding(.top, 6)
    }

    private func eventRow(_ event: EnergyEvent, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(event.time)
                .font(.caption2).foregroundStyle(.secondary)
                .frame(width: 42, alignment: .leading)
                .padding(.top, 2)

            Circle().fill(.black).frame(width: 9, height: 9).padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title).font(.subheadline).fontWeight(.semibold)
                Text(event.note).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if event.delta != 0 {
                Text(event.delta > 0 ? "+\(event.delta)" : "\(event.delta)")
                    .font(.footnote).fontWeight(.bold)
                    .foregroundStyle(event.delta > 0
                        ? Color(red: 0.3, green: 0.49, blue: 0.16)
                        : Color(red: 0.6, green: 0.36, blue: 0.31))
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if !isLast {
                Divider()
            }
        }
    }

    // MARK: - 悬浮「按住记录」按钮（照原型的按住交互）
    private var voiceButton: some View {
        HStack(spacing: 9) {
            Image(systemName: justSaved ? "checkmark" : "mic")
            Text(justSaved ? C.t("today.voiceLabelSaved") : (isRecording ? C.t("today.voiceLabelRecording") : C.t("today.voiceLabelIdle")))
                .font(.footnote).fontWeight(.bold)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22)
        .frame(height: 48)
        .background(.black)
        .clipShape(Capsule())
        .scaleEffect(isRecording ? 1.06 : 1.0)
        .animation(.spring(response: 0.3), value: isRecording)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isRecording {
                        isRecording = true
                        justSaved = false
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                }
                .onEnded { _ in
                    isRecording = false
                    justSaved = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        justSaved = false
                    }
                }
        )
    }
}

#Preview {
    TodayView()
}
