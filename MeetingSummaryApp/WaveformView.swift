//
//  WaveformView.swift
//  MeetingSummaryApp
//
//  Created by 최영기 on 11/23/25.
//

import SwiftUI

struct WaveformView: View {
    let level: CGFloat   // 0.0 ~ 1.0

    var body: some View {
        GeometryReader { geo in
            let height = max(level, 0.05) * geo.size.height

            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: 8)
                    .frame(width: geo.size.width * 0.6,
                           height: height)
                    .opacity(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
