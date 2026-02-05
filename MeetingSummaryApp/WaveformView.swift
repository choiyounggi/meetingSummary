//
//  WaveformView.swift
//  MeetingSummaryApp
//
//  Created by 최영기 on 11/23/25.
//

import SwiftUI

struct WaveformView: View {
    let level: CGFloat   // 0.0 ~ 1.0
    private let barCount = 24

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 3) {
                ForEach(0..<barCount, id: \.self) { index in
                    let distance = abs(CGFloat(index) - CGFloat(barCount) / 2.0) / (CGFloat(barCount) / 2.0)
                    let scale = max(0.08, (1.0 - distance * 0.7) * max(level, 0.05))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(for: level))
                        .frame(height: geo.size.height * scale)
                        .animation(.easeInOut(duration: 0.12), value: level)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func barColor(for level: CGFloat) -> Color {
        if level > 0.6 {
            return Color(nsColor: NSColor(red: 0.95, green: 0.3, blue: 0.3, alpha: 0.85))
        } else if level > 0.3 {
            return Color(nsColor: NSColor(red: 0.3, green: 0.7, blue: 0.5, alpha: 0.75))
        } else {
            return Color(nsColor: NSColor(red: 0.55, green: 0.55, blue: 0.62, alpha: 0.5))
        }
    }
}
