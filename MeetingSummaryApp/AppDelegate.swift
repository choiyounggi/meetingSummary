//
//  AppDelegate.swift
//  MeetingSummaryApp
//
//  Created by 최영기 on 11/23/25.
//

import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 메뉴바 아이템 생성
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "waveform",
                accessibilityDescription: "Meeting Summary"
            )
            button.image?.isTemplate = true  // 다크/라이트 모드 자동
        }

        // 메뉴 구성
        let menu = NSMenu()

        let openItem = NSMenuItem(
            title: "창 열기",
            action: #selector(openMainWindow),
            keyEquivalent: "o"
        )
        openItem.target = self

        let quitItem = NSMenuItem(
            title: "종료",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self

        menu.addItem(openItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func openMainWindow() {
        // 앱을 앞으로
        NSApp.activate(ignoringOtherApps: true)

        // ✅ 아직 한 번도 안 만들었으면 생성
        if window == nil {
            let contentView = ContentView()
            let hostingController = NSHostingController(rootView: contentView)

            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 360),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            win.center()
            win.title = "회의 녹음 & 요약"
            win.contentViewController = hostingController

            // ✅ 닫혀도 메모리에서 해제하지 않음
            win.isReleasedWhenClosed = false

            self.window = win
        }

        // ✅ 이미 있으면(닫혀 있어도) 그냥 앞으로 가져오기
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
