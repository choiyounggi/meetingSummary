# MeetingSummary (회의록 요약 서비스)

회의 내용을 녹음, STT 변환 및 요약해서 노션에 정리해 주는 macOS 앱이다.
Whisper로 STT 변환 후 Claude로 요약하여 Notion에 회의록을 등록한다.

## 기술 스택

- **언어**: Swift 5
- **프레임워크**: SwiftUI, AVFoundation, Combine
- **플랫폼**: macOS (AppKit + SwiftUI)
- **외부 API**: OpenAI Whisper (STT), Anthropic Claude (요약), Notion API, Slack Webhook

## 프로젝트 구조

```
meetingSummary/
├── MeetingSummaryApp.xcodeproj    # Xcode 프로젝트
├── MeetingSummaryApp/             # 앱 소스
│   ├── MeetingSummaryApp.swift    # @main 앱 진입점
│   ├── AppDelegate.swift          # 메뉴바 아이콘 및 윈도우 관리
│   ├── ContentView.swift          # 탭 네비게이션 컨테이너
│   ├── AudioRecorder.swift        # 녹음, STT, 요약, Notion 업로드 핵심 로직
│   ├── WaveformView.swift         # 실시간 파형 시각화
│   ├── WindowExtensions.swift     # Always-on-top 윈도우 설정
│   ├── Info.plist                 # 앱 권한 및 설정
│   └── Assets.xcassets/           # 앱 아이콘 및 색상 에셋
├── MeetingSummaryView.swift       # 녹음 및 요약 탭 뷰
├── SettingsView.swift             # 설정 탭 뷰 (API 키 관리)
├── SettingsManager.swift          # 설정값 싱글턴 (UserDefaults)
└── CLAUDE.md
```

## 빌드 및 실행

- Xcode에서 `MeetingSummaryApp.xcodeproj`를 열고 빌드한다.
- 마이크 권한이 필요하다 (`Info.plist`에 `NSMicrophoneUsageDescription` 설정됨).

## 코딩 컨벤션

### 공통

- 모든 응답과 주석은 **한글**을 우선 사용한다.
- 파일 인코딩은 UTF-8을 사용한다.
- 모든 커밋 메시지는 한글로 작성한다.
- 모든 브랜치명은 영어로 작성한다.

### Swift

- SwiftUI 선언형 패턴을 따른다.
- `@StateObject`, `@Published` 등 Combine 기반 상태 관리를 사용한다.
- MARK 주석(`// MARK: -`)으로 코드 영역을 구분한다.
- 접근 제어는 필요한 최소 수준으로 설정한다 (`private` 우선).
- SF Symbols를 아이콘으로 사용한다.
- 시스템 색상(`NSColor` 기반)을 사용하여 다크/라이트 모드를 자동 지원한다.
