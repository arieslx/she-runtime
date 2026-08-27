//
//  ContentView.swift
//  sheRuntime
//
//  Created by ari on 2026/8/27.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var healthKitManager = HealthKitManager()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("sheRuntime")
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                Text(healthKitManager.statusMessage)
                    .foregroundStyle(.secondary)

                Text("\(healthKitManager.stepCount)")
                    .font(.system(size: 56, weight: .bold))

                Text("今日步数")
                    .foregroundStyle(.secondary)

                Button("连接 Apple Health") {
                    Task {
                        await healthKitManager.requestAuthorizationAndLoadSteps()
                    }
                }
                .buttonStyle(.borderedProminent)

                Divider()

                NavigationLink("打开 Audio Probe") {
                    AudioProbeView()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .navigationTitle("调试探针")
        }
    }
}

#Preview {
    ContentView()
}
