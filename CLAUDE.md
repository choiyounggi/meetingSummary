# MeetingSummary (회의록 요약 서비스)

회의 내용을 녹음, STT 변환 및 요약해서 Notion에 정리하고, GitHub 위키에 자동 커밋하는 macOS 앱이다.
Whisper로 STT 변환 후 위키 기반 컨텍스트를 주입하여 Claude로 요약하고, Notion 등록 → Slack 알림 → GitHub 위키 푸시까지 자동화한다.

## 기술 스택

- **언어**: Swift 5
- **프레임워크**: SwiftUI, AVFoundation, Combine
- **플랫폼**: macOS (AppKit + SwiftUI)
- **외부 API**: OpenAI Whisper (STT), Anthropic Claude (요약/화자 분리), Notion API, Slack Webhook, GitHub Contents API

## 처리 플로우

```
[토큰 검증] → [Whisper STT] → (화자분리 ON 시) [Claude 화자 추론] → [Claude 요약] → [Notion 등록] → [Slack 알림] → [GitHub 위키 푸시]
```

- 녹음 버튼: 토큰 검증 → 마이크 권한 → 녹음 → STT → (화자분리) → 요약 → 등록
- 드래그 앤 드롭: 파일 로드 → 토큰 검증 → STT → (화자분리) → 요약 → 등록
- 20MB 초과 파일: 10분 단위 청크 분할 → 병렬 STT (실패 시 최대 2회 재시도)
- 화자 분리 (Claude 추론): Whisper verbose_json 타임스탬프 + Claude 문맥 분석 (추가 설치 불필요)
- 화자 분리 (pyannote): pyannote.audio 음성 특성 분석으로 정확한 화자 구분 (Python + torch 필요)

## 프로젝트 구조

```
meetingSummary/
├── MeetingSummaryApp.xcodeproj    # Xcode 프로젝트
├── MeetingSummaryApp/             # 앱 소스 (FileSystemSynchronizedRootGroup)
│   ├── MeetingSummaryApp.swift    # @main 앱 진입점
│   ├── AppDelegate.swift          # 메뉴바 아이콘 및 윈도우 관리
│   ├── ContentView.swift          # 탭 네비게이션 컨테이너
│   ├── AudioRecorder.swift        # 녹음, STT, 요약, Notion/GitHub 업로드, 토큰 검증
│   ├── WaveformView.swift         # 실시간 파형 시각화
│   ├── WindowExtensions.swift     # Always-on-top 윈도우 설정
│   ├── Info.plist                 # 앱 권한 및 설정
│   └── Assets.xcassets/           # 앱 아이콘 및 색상 에셋
├── MeetingSummaryView.swift       # 녹음 및 요약 탭 뷰
├── SettingsView.swift             # 설정 탭 뷰 (API 키, 위키 경로 관리)
├── SettingsManager.swift          # 설정값 싱글턴 (UserDefaults, Security-Scoped Bookmark)
├── WikiContextLoader.swift        # 위키 문서 로드 및 STT 보정 사전 기반 시스템 프롬프트 생성
├── CLAUDE.md
└── README.md
```

> **참고**: 이전에 존재하던 `scripts/` 폴더(pyannote Python 스크립트)는 제거되었다. 화자 분리는 Claude API로 처리한다.

## 주요 모듈 설명

### AudioRecorder.swift
- `ProcessingStage`: idle → validating → transcribing → summarizing → uploading → completed
- `validateAllTokens()`: OpenAI, Anthropic, Notion, GitHub 토큰을 병렬로 유효성 검증
- `transcribeLargeAudio()`: 대용량 오디오를 청크 분할 → 병렬 STT (재시도 포함)
- `startTranscriptionWithDiarization()`: Whisper verbose_json STT → Claude 화자 추론 → 화자 라벨링된 텍스트 생성
- `identifySpeakersWithClaude()`: 타임스탬프 포함 STT 텍스트에서 Claude로 화자 구분
- `summarizeWithClaude()`: WikiContextLoader로 위키 기반 시스템 프롬프트 주입
- `pushSummaryToGitHub()`: GitHub Contents API로 `dev-rsquare/rtb-wiki` 레포에 회의록 커밋

### WikiContextLoader.swift
- 위키 디렉토리에서 3개 핵심 문서를 읽어 컨텍스트 생성:
  - `team/company/rsquare-profile.md` (회사 프로필)
  - `rtb-common/RTB_CONTEXT.md` (시스템 개요/도메인 모델)
  - `rtb-common/glossary.md` (용어사전)
- STT 보정 사전: 오인식 패턴 → 정확한 표기 매핑 테이블 내장
- 팀원 이름 보정 테이블 포함
- 세션당 1회 로드 후 캐싱, 위키 미설정 시 하드코딩 폴백 프롬프트 사용

### SettingsManager.swift
- `openAIKey`, `anthropicKey`, `notionKey`, `githubToken`, `wikiPath`, `diarizationMode`, `huggingFaceToken`, `pythonPath` 관리
- Security-Scoped Bookmark으로 샌드박스 환경에서 위키 폴더 접근 유지

## 빌드 및 실행

- Xcode에서 `MeetingSummaryApp.xcodeproj`를 열고 빌드한다.
- 마이크 권한이 필요하다 (`Info.plist`에 `NSMicrophoneUsageDescription` 설정됨).
- App Sandbox 해제됨 (`ENABLE_APP_SANDBOX = NO`): pyannote 모드에서 Python Process 실행이 필요하므로 비활성화

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
