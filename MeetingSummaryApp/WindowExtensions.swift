//
//  WindowExtensions.swift
//  MeetingSummaryApp
//
//  Created by 최영기 on 11/25/25.
//

import SwiftUI
import AppKit

struct AlwaysOnTopWindowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(WindowAccessor())
    }

    private struct WindowAccessor: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            let view = NSView()

            // 뷰가 윈도우에 붙은 이후에 윈도우 레벨을 올려준다
            DispatchQueue.main.async {
                if let window = view.window {
                    // 항상 최앞단 + 풀스크린 앱 위에서도 보이도록
                    window.level = .floating
                    window.collectionBehavior.insert(.canJoinAllSpaces)
                    window.collectionBehavior.insert(.fullScreenAuxiliary)
                }
            }

            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {}
    }
}

extension View {
    func alwaysOnTopWindow() -> some View {
        self.modifier(AlwaysOnTopWindowModifier())
    }
}
