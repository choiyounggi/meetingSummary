//
//  MeetingSummaryAppApp.swift
//  MeetingSummaryApp
//
//  Created by 최영기 on 11/23/25.
//

import SwiftUI

@main
struct MeetingSummaryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .alwaysOnTopWindow()
        }
        Settings {
            EmptyView()
        }
    }
}
