//
//  ContentView.swift
//  sheRuntime
//
//  Created by ari on 2026/8/27.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("sheRuntime")
                    .font(.largeTitle)
                    .fontWeight(.semibold)

                NavigationLink("打开 HealthKit Probe") {
                    HealthKitProbeView()
                }
                .buttonStyle(.bordered)

                NavigationLink("打开 Audio Probe") {
                    AudioProbeView()
                }
                .buttonStyle(.bordered)

                NavigationLink("打开 BLE Probe") {
                    StopWatchBLEProbeView()
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
