# MeetingSummary

회의 내용을 녹음하고, STT 변환 및 요약하여 Notion 등록 → Slack 알림 → GitHub 위키 자동 커밋까지 원스톱으로 처리하는 macOS 앱입니다.

## 주요 기능

- 회의 음성 녹음 (마이크 직접 녹음 또는 음성 파일 드래그 앤 드롭)
- OpenAI Whisper를 통한 STT(음성→텍스트) 변환
  - 20MB 초과 대용량 파일은 10분 단위 청크 분할 후 병렬 처리
  - 실패 시 최대 2회 자동 재시도
- 화자 분리 3모드 지원
  - **OFF**: 화자 분리 없이 텍스트 그대로 요약
  - **Claude 추론**: Whisper 타임스탬프 + Claude 문맥 분석 (추가 설치 불필요)
  - **pyannote**: pyannote.audio 음성 특성 분석으로 정밀 화자 구분 (Python + torch 필요)
- 위키 기반 STT 보정 사전으로 도메인 용어 자동 교정
- Wiki-RAG 시맨틱 검색으로 회의 주제와 관련된 위키 컨텍스트 자동 주입
- Anthropic Claude를 통한 회의록 요약 생성
- Notion 페이지로 회의록 자동 등록
- Slack 웹훅을 통한 완료 알림
- GitHub 위키 레포에 회의록 마크다운 자동 커밋/푸시
- 처리 시작 전 모든 API 토큰 유효성 자동 검증
- 처리 중 언제든 취소 가능
- 실시간 파형 시각화 및 녹음 재생

## 처리 플로우

```
토큰 검증 → STT 변환 → (화자분리) → Claude 요약 → Notion 등록 → Slack 알림 → GitHub 위키 푸시
```

- 녹음 버튼: 토큰 검증 → 마이크 권한 → 녹음 → STT → (화자분리) → 요약 → 등록
- 드래그 앤 드롭: 파일 로드 → 토큰 검증 → STT → (화자분리) → 요약 → 등록
- 20MB 초과 파일: 10분 단위 청크 분할 → 병렬 STT (실패 시 최대 2회 재시도)

## 실행 방법

### 방법 1: Xcode에서 직접 빌드

1. `MeetingSummaryApp.xcodeproj`를 Xcode에서 엽니다.
2. 빌드 타겟을 확인하고 `Cmd + R`로 실행합니다.

### 방법 2: 아카이브 익스포트

1. Xcode에서 `Product > Archive`로 아카이브를 생성합니다.
2. 아카이브 완료 후 `Distribute App > Copy App`을 선택하여 익스포트합니다.
3. 익스포트된 폴더 내부의 `MeetingSummaryApp.app` 파일을 실행합니다.

## 설정

앱 실행 후 **설정** 탭에서 아래 항목들을 입력합니다.

### API 키

| 키 | 용도 | 발급처 |
|---|---|---|
| OpenAI API Key | Whisper STT 변환 | https://platform.openai.com |
| Anthropic API Key | Claude 회의록 요약 | https://console.anthropic.com |
| Notion API Key | 회의록 페이지 등록 | https://www.notion.so/my-integrations |
| GitHub Token | 위키 레포 회의록 커밋 | https://github.com/settings/tokens (Contents write 권한 필요) |
| Notion Database ID | 회의록이 저장될 Notion 데이터베이스 | Notion 데이터베이스 URL에서 확인 |

### 화자 분리

설정 탭의 **화자 분리** 카드에서 모드를 선택합니다.

| 모드 | 설명 | 추가 설정 |
|---|---|---|
| OFF | 화자 분리 없이 STT 텍스트를 그대로 요약 | 없음 |
| Claude 추론 | Whisper 타임스탬프 + Claude 문맥 분석 | 없음 |
| pyannote (고급) | pyannote.audio 음성 특성 분석 | HuggingFace Token, Python 경로 |

### 위키 경로 (선택)

RTB 위키 폴더를 설정하면 회사/도메인 정보를 요약 컨텍스트로 자동 주입하여 요약 품질이 향상됩니다.

- 설정 탭에서 폴더 선택 버튼으로 위키 루트 디렉토리를 지정합니다.
- 미설정 시 기본 내장 컨텍스트로 동작합니다.

**Wiki-RAG 서버**: `http://localhost:8686` (기본값)으로 시맨틱 검색 기반 위키 컨텍스트를 자동 주입합니다. wiki-rag 서버가 실행 중이면 회의 내용과 관련된 위키 문서를 자동으로 검색하여 요약 품질을 높입니다.

### 연동 설정

| 항목 | 설명 | 예시 |
|---|---|---|
| Slack Webhook URL | 요약 완료 시 알림을 보낼 채널 웹훅 | `https://hooks.slack.com/services/...` |
| GitHub Wiki 레포 | 회의록이 커밋될 GitHub 레포 | `dev-rsquare/rtb-wiki` |
| 회의록 저장 경로 | 위키 레포 내 회의록 저장 디렉토리 | `rtb-unified/meetings` |

## 기술 스택

- **언어**: Swift 5
- **프레임워크**: SwiftUI, AVFoundation, Combine
- **플랫폼**: macOS (AppKit + SwiftUI)
- **외부 API**: OpenAI Whisper, Anthropic Claude, Notion API, Slack Webhook, GitHub Contents API, Wiki-RAG HTTP API
