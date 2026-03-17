//
//  WaveformView.swift
//  MeetingSummaryApp
//
//  Created by 최영기 on 11/23/25.
//

import SwiftUI

struct WaveformView: View {
    let level: CGFloat   // 0.0 ~ 1.0
    private let barCount = 32

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    let distance = abs(CGFloat(index) - CGFloat(barCount) / 2.0) / (CGFloat(barCount) / 2.0)
                    let scale = max(0.08, (1.0 - distance * 0.7) * max(level, 0.05))

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(barColor(for: level))
                        .frame(height: geo.size.height * scale)
                        .animation(.spring(response: 0.15, dampingFraction: 0.7), value: level)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - 인디고 테마 바 컬러
    private func barColor(for level: CGFloat) -> Color {
        if level > 0.6 {
            // 높은 레벨: 따뜻한 코랄/레드
            return Color(nsColor: NSColor(red: 0.95, green: 0.35, blue: 0.35, alpha: 0.9))
        } else if level > 0.3 {
            // 중간 레벨: 인디고 액센트
            return Color(nsColor: NSColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 0.7))
        } else {
            // 낮은 레벨: 뉴트럴
            return Color(nsColor: NSColor(red: 0.45, green: 0.45, blue: 0.52, alpha: 0.4))
        }
    }
}
