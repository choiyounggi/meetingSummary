# MeetingSummary

회의 내용을 녹음하고, STT 변환 및 요약하여 Notion에 자동 등록하는 macOS 앱입니다.

## 주요 기능

- 회의 음성 녹음 (마이크 직접 녹음 또는 음성 파일 드래그 앤 드롭)
- OpenAI Whisper를 통한 STT(음성→텍스트) 변환
- Anthropic Claude를 통한 회의록 요약 생성
- Notion 페이지로 회의록 자동 등록
- Slack 웹훅을 통한 완료 알림
- 실시간 파형 시각화 및 녹음 재생

## 실행 방법

### 방법 1: Xcode에서 직접 빌드

1. `MeetingSummaryApp.xcodeproj`를 Xcode에서 엽니다.
2. 빌드 타겟을 확인하고 `Cmd + R`로 실행합니다.

### 방법 2: 아카이브 익스포트

1. Xcode에서 `Product > Archive`로 아카이브를 생성합니다.
2. 아카이브 완료 후 `Distribute App > Copy App`을 선택하여 익스포트합니다.
3. 익스포트된 폴더 내부의 `MeetingSummaryApp.app` 파일을 실행합니다.

## 설정

앱 실행 후 **설정** 탭에서 아래 API 키를 입력하고 저장합니다.

| 키 | 용도 | 발급처 |
|---|---|---|
| OpenAI API Key | Whisper STT 변환 | https://platform.openai.com |
| Anthropic API Key | Claude 회의록 요약 | https://console.anthropic.com |
| Notion API Key | 회의록 페이지 등록 | https://www.notion.so/my-integrations |

## 기술 스택

- **언어**: Swift 5
- **프레임워크**: SwiftUI, AVFoundation, Combine
- **플랫폼**: macOS (AppKit + SwiftUI)
- **외부 API**: OpenAI Whisper, Anthropic Claude, Notion API, Slack Webhook
