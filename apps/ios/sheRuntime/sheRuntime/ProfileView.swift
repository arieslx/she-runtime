//
//  ProfileView.swift
//  sheRuntime
//
//  我的页（个人基线 / 数据源 / 隐私）。静态页面 + 假数据。
//  照产品原型 她律原型01.html 的 Profile 页。
//  艾瑞的调试探针入口收在最下面。
//

import SwiftUI

struct ProfileView: View {
    private let bg = Color(red: 0.957, green: 0.957, blue: 0.937)

    var body: some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header
                        baselineCard
                        sectionTitle(C.t("profile.dataSourcesTitle"), trailing: C.t("profile.dataSourcesTrailing"))
                        settingCard(ProfileMock.dataSources)
                        sectionTitle(C.t("profile.privacyTitle"), trailing: "")
                        settingCard(ProfileMock.privacyRows)

                        // 艾瑞的调试探针入口
                        NavigationLink("打开调试探针（艾瑞的测试页）") {
                            ContentView()
                        }
                        .font(.caption)
                        .padding(.top, 10)

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Circle().fill(.black).frame(width: 58, height: 58)
                .overlay(Text(ProfileMock.name.prefix(1))
                    .font(.title2).fontWeight(.bold).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 4) {
                Text(ProfileMock.name).font(.title3).fontWeight(.semibold)
                Text(ProfileMock.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 28))
    }

    private var baselineCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(C.t("profile.baselineSmall").uppercased()).font(.caption2).fontWeight(.bold)
                .foregroundStyle(.white.opacity(0.6)).tracking(1)
            Text(ProfileMock.baselineTitle).font(.title2).fontWeight(.bold)
                .foregroundStyle(.white).padding(.top, 8)
            Text(C.t("profile.baselineBody")).font(.caption)
                .foregroundStyle(.white.opacity(0.75)).padding(.top, 2)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(.white)
                        .frame(width: geo.size.width * ProfileMock.coverage)
                }
            }
            .frame(height: 8)
            .padding(.top, 16)

            HStack {
                Text(C.t("profile.coverageLabel")).font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Text("\(Int(ProfileMock.coverage * 100))%").font(.caption2)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.top, 7)
        }
        .padding(20)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }

    private func sectionTitle(_ title: String, trailing: String) -> some View {
        HStack {
            Text(title).font(.subheadline).fontWeight(.semibold)
            Spacer()
            Text(trailing).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private func settingCard(_ rows: [SettingRow]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title).font(.subheadline).fontWeight(.medium)
                        Text(row.note).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(row.value).font(.caption).fontWeight(.semibold)
                        .foregroundStyle(row.connected
                            ? Color(red: 0.3, green: 0.49, blue: 0.16) : .secondary)
                }
                .padding(16)
                if index != rows.count - 1 { Divider() }
            }
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

#Preview { ProfileView() }
