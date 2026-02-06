//
//  ContentView.swift
//  MeetingSummaryApp
//
//  Created by 최영기 on 11/23/25.
//

import SwiftUI
import UniformTypeIdentifiers

enum MainTab: String, CaseIterable, Identifiable {
    case meeting = "음성 기록"
    case settings = "설정"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .meeting: return "waveform"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: MainTab = .meeting
    @StateObject private var recorder = AudioRecorder()

    var body: some View {
        VStack(spacing: 0) {
            // 상단 헤더
            HStack {
                Text("회의록 요약")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 6)

            // 커스텀 탭 바
            HStack(spacing: 0) {
                ForEach(MainTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    } label: {
                        VStack(spacing: 6) {
                            HStack(spacing: 5) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 12))
                                Text(tab.rawValue)
                                    .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                            }
                            .foregroundColor(selectedTab == tab ? .primary : .secondary)
                            .frame(maxWidth: .infinity)

                            // 선택 인디케이터
                            Rectangle()
                                .fill(selectedTab == tab ? Color.primary : Color.clear)
                                .frame(height: 2)
                                .cornerRadius(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            Divider()
                .padding(.top, 2)

            // 탭에 따른 콘텐츠 (ZStack + opacity로 뷰 상태 유지)
            ZStack {
                ScrollView {
                    MeetingSummaryView(recorder: recorder)
                        .padding(.top, 4)
                }
                .opacity(selectedTab == .meeting ? 1 : 0)

                ScrollView {
                    SettingsView()
                        .padding(.top, 4)
                }
                .opacity(selectedTab == .settings ? 1 : 0)
            }
        }
        .frame(minWidth: 400, idealWidth: 480, maxWidth: 520,
               minHeight: 450, idealHeight: 520, maxHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
