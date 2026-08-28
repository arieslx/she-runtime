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

    var body: some View {
        NavigationStack {
            DataPrivacyView(
                stopWatchBLE: appServices.stopWatchBLE,
                permissions: appServices.dataPermissions,
                audioPipeline: appServices.stopWatchAudioPipeline
            )
        }
    }
}

#Preview { ProfileView().environmentObject(AppServices()) }
