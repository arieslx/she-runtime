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
    @EnvironmentObject private var appServices: AppServices
    /// 路演演示模式：开 = 规律页渲染打包的示例数据（真实用户数据跑出的例子）
    @AppStorage("demo_mode_enabled") private var demoModeEnabled = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DataPrivacyView(
                    stopWatchBLE: appServices.stopWatchBLE,
                    permissions: appServices.dataPermissions,
                    audioPipeline: appServices.stopWatchAudioPipeline
                )
                demoModeRow
            }
        }
    }

    private var demoModeRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: $demoModeEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(C.t("profile_demo.label"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                    Text(C.t("profile_demo.note"))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(AppPalette.faint)
                }
            }
            .tint(AppPalette.green)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(AppPalette.background)
    }
}

#Preview { ProfileView().environmentObject(AppServices()) }
