# MeetingSummary

**English** | [한국어](README.ko.md)

A macOS app that records a meeting, runs STT and summarization, and handles
everything in one pass: Notion registration → Slack notification → automatic
GitHub wiki commit.

## Features

- Meeting audio recording (direct mic recording, or drag-and-drop of an audio file)
- STT (speech → text) via OpenAI Whisper
  - Files over 20MB are split into 10-minute chunks and processed in parallel
  - Up to 2 automatic retries on failure
- Three speaker-diarization modes
  - **OFF**: summarize the raw text without speaker separation
  - **Claude inference**: Whisper timestamps + Claude context analysis (no extra installs)
  - **pyannote**: precise speaker separation via pyannote.audio acoustic analysis (requires Python + torch)
- Wiki-based STT correction dictionary auto-fixes domain terms
- Wiki-RAG semantic search auto-injects wiki context relevant to the meeting topic
- Meeting-minutes summarization via Anthropic Claude
- Automatic registration as a Notion page
- Completion notification via Slack webhook
- Automatic markdown commit/push of the minutes to a GitHub wiki repo
- All API tokens validated automatically before processing starts
- Cancellable at any point during processing
- Real-time waveform visualization and recording playback

## Processing flow

```
token validation → STT → (diarization) → Claude summary → Notion → Slack → GitHub wiki push
```

- Record button: token validation → mic permission → record → STT → (diarization) → summary → registration
- Drag & drop: file load → token validation → STT → (diarization) → summary → registration
- Files over 20MB: 10-minute chunking → parallel STT (up to 2 retries on failure)

## Running it

### Option 1: build directly in Xcode

1. Open `MeetingSummaryApp.xcodeproj` in Xcode.
2. Check the build target and run with `Cmd + R`.

### Option 2: archive export

1. In Xcode, create an archive via `Product > Archive`.
2. After archiving, choose `Distribute App > Copy App` to export.
3. Run `MeetingSummaryApp.app` inside the exported folder.

## Configuration

After launching, fill in the following under the **Settings** tab.

### API keys

| Key | Purpose | Where to get it |
|---|---|---|
| OpenAI API Key | Whisper STT | https://platform.openai.com |
| Anthropic API Key | Claude meeting summarization | https://console.anthropic.com |
| Notion API Key | Minutes page registration | https://www.notion.so/my-integrations |
| GitHub Token | Committing minutes to the wiki repo | https://github.com/settings/tokens (needs Contents write) |
| Notion Database ID | The Notion database that stores the minutes | from the Notion database URL |

### Speaker diarization

Pick a mode in the **Speaker diarization** card of the Settings tab.

| Mode | Description | Extra setup |
|---|---|---|
| OFF | Summarize the STT text as-is, no separation | none |
| Claude inference | Whisper timestamps + Claude context analysis | none |
| pyannote (advanced) | pyannote.audio acoustic analysis | HuggingFace token, Python path |

### Wiki path (optional)

Pointing the app at a wiki folder injects company/domain knowledge into the
summarization context, improving summary quality.

- Use the folder picker in the Settings tab to select the wiki root directory.
- Without it, a built-in default context is used.

**Wiki-RAG server**: semantic-search wiki context is auto-injected from
`http://localhost:8686` (default). When a wiki-rag server is running, wiki
documents relevant to the meeting are retrieved automatically to raise summary
quality.

### Integrations

| Item | Description | Example |
|---|---|---|
| Slack Webhook URL | The channel webhook notified when a summary completes | `https://hooks.slack.com/services/...` |
| GitHub wiki repo | The GitHub repo the minutes are committed to | `dev-rsquare/rtb-wiki` |
| Minutes path | The directory inside the wiki repo for minutes | `rtb-unified/meetings` |

## Tech stack

- **Language**: Swift 5
- **Frameworks**: SwiftUI, AVFoundation, Combine
- **Platform**: macOS (AppKit + SwiftUI)
- **External APIs**: OpenAI Whisper, Anthropic Claude, Notion API, Slack Webhook, GitHub Contents API, Wiki-RAG HTTP API
