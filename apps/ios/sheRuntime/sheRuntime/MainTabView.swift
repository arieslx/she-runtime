//
//  MainTabView.swift
//  sheRuntime
//
//  App 的主壳：底部 5 个 tab（今日 / 地图 / 洞察 / 问问 / 我的）。
//  照产品原型的底部导航。全部页面已做，都是静态页面 + 假数据。
//

import SwiftUI

struct MainTabView: View {
    // SHOT_PAGE 环境变量（0-4）指定启动时选中的 tab，供 simctl 截图排查用；日常运行不受影响
    @State private var selection: Int = {
        Int(ProcessInfo.processInfo.environment["SHOT_PAGE"] ?? "") ?? 0
    }()

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem { Label(C.t("tabs.today"), systemImage: "sun.max") }
                .tag(0)

            MapView()
                .tabItem { Label(C.t("tabs.map"), systemImage: "chart.line.uptrend.xyaxis") }
                .tag(1)

            InsightsView()
                .tabItem { Label(C.t("tabs.insights"), systemImage: "lightbulb") }
                .tag(2)

            AskView()
                .tabItem { Label(C.t("tabs.ask"), systemImage: "bubble.left.and.bubble.right") }
                .tag(3)

            ProfileView()
                .tabItem { Label(C.t("tabs.profile"), systemImage: "person") }
                .tag(4)
        }
        .tint(.black)
    }
}

#Preview {
    MainTabView()
}
