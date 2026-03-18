//
//  ContentView.swift
//  MeetingSummaryApp
//
//  Created by 최영기 on 11/23/25.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 디자인 상수

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
            // MARK: - 상단 헤더
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(nsColor: .labelColor))
                        .frame(width: 7, height: 7)
                    Text("Meeting Summary")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // MARK: - 탭 바
            HStack(spacing: 2) {
                ForEach(MainTab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12))
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: selectedTab == tab ? .medium : .regular))
                        }
                        .foregroundColor(selectedTab == tab ? .primary : .secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab
                                      ? Color(nsColor: .controlBackgroundColor)
                                      : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Divider()
                .opacity(0.4)

            // MARK: - 콘텐츠
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
