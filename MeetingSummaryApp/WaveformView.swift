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

    // MARK: - 뉴트럴 바 컬러
    private func barColor(for level: CGFloat) -> Color {
        if level > 0.6 {
            return Color(nsColor: NSColor(red: 0.85, green: 0.30, blue: 0.25, alpha: 0.95))
        } else if level > 0.3 {
            return Color(nsColor: NSColor(red: 0.25, green: 0.25, blue: 0.28, alpha: 0.85))
        } else {
            return Color(nsColor: NSColor(red: 0.40, green: 0.40, blue: 0.43, alpha: 0.60))
        }
    }
}
