//
//  ContentView.swift
//  MeetingSummaryApp
//
//  Created by 최영기 on 11/23/25.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 디자인 상수
private enum DesignTokens {
    // 액센트 인디고
    static let accentIndigo = Color(nsColor: NSColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 1.0))
    static let accentLight = Color(nsColor: NSColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 0.10))
    static let separatorOpacity: CGFloat = 0.2
}

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
                // 왼쪽: 아이콘 + 앱 이름
                HStack(spacing: 7) {
                    Image(systemName: "waveform.badge.mic")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DesignTokens.accentIndigo)
                    Text("Meeting Summary")
                        .font(.system(size: 16, weight: .semibold))
                }

                Spacer()

                // 오른쪽: 버전 배지
                Text("v1.0")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .separatorColor).opacity(DesignTokens.separatorOpacity))
                    )
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // 헤더 하단 gradient 구분선
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            DesignTokens.accentIndigo.opacity(0.25),
                            Color(nsColor: .separatorColor).opacity(0.08)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 16)

            // MARK: - 커스텀 탭 바
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
                                    .font(.system(size: 13))
                                Text(tab.rawValue)
                                    .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                            }
                            .foregroundColor(selectedTab == tab ? DesignTokens.accentIndigo : .secondary)
                            .frame(maxWidth: .infinity)

                            // 선택 인디케이터 (인디고 underline)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(selectedTab == tab ? DesignTokens.accentIndigo : Color.clear)
                                .frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .background(
                Color(nsColor: .windowBackgroundColor)
                    .opacity(0.85)
            )

            Divider()
                .opacity(0.5)
                .padding(.top, 2)

            // MARK: - 탭에 따른 콘텐츠 (ZStack + opacity로 뷰 상태 유지)
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
