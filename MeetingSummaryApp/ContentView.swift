//
//  ContentView.swift
//  MeetingSummaryApp
//
//  Created by 최영기 on 11/23/25.
//

import SwiftUI
import UniformTypeIdentifiers

enum MainTab: String, CaseIterable, Identifiable {
    case meeting = "회의록 요약"
    case settings = "설정"
    var id: String { rawValue }
}

struct ContentView: View {
    @State private var selectedTab: MainTab = .meeting

    var body: some View {
        VStack(spacing: 0) {
            // 상단 탭 (SegmentedControl 느낌)
            Picker("", selection: $selectedTab) {
                ForEach(MainTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.all, 12)

            Divider()

            // 탭에 따른 콘텐츠
            switch selectedTab {
            case .meeting:
                MeetingSummaryView()
            case .settings:
                SettingsView()
            }
        }
        .frame(width: 480, height: 460)
        .padding(.bottom, 8)
    }
}

