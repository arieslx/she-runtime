//
//  sheRuntimeApp.swift
//  sheRuntime
//
//  Created by ari on 2026/8/27.
//

import SwiftUI
import SwiftData

@main
struct sheRuntimeApp: App {
    @StateObject private var appServices = AppServices()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            TimelineRecord.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(appServices)
                .preferredColorScheme(.light)
                .task {
                    appServices.activate()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
