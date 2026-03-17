//
//  MeetingSummaryView.swift
//  MeetingSummaryApp
//
//  Created by 최영기 on 12/12/25.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 디자인 토큰
private enum DesignToken {
    static let accentIndigo = Color(nsColor: NSColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 1.0))
    static let successGreen = Color(nsColor: NSColor(red: 0.16, green: 0.72, blue: 0.53, alpha: 1.0))
    static let errorRed = Color(nsColor: NSColor(red: 0.91, green: 0.30, blue: 0.24, alpha: 1.0))

    static let cardCornerRadius: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 12
}

// MARK: - 카드 섹션 컴포넌트
struct CardSection<Content: View>: View {
    let title: String
    let icon: String
    var isExpanded: Binding<Bool>? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 섹션 헤더
            HStack {
                HStack(spacing: 8) {
                    // 인디고 배경 원 안에 흰색 아이콘
                    ZStack {
                        Circle()
                            .fill(DesignToken.accentIndigo)
                            .frame(width: 20, height: 20)
                        Image(systemName: icon)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                }

                Spacer()

                if let binding = isExpanded {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            binding.wrappedValue.toggle()
                        }
                    } label: {
                        Image(systemName: binding.wrappedValue ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 22, height: 22)
                            .background(
                                Circle()
                                    .fill(Color(nsColor: .separatorColor).opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if isExpanded?.wrappedValue != false {
                Divider()
                    .opacity(0.1)
                    .padding(.horizontal, 16)

                content()
                    .padding(DesignToken.cardPadding)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: DesignToken.cardCornerRadius)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignToken.cardCornerRadius)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}

// MARK: - 상태 배지
struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(color.opacity(0.08))
        )
    }
}

// MARK: - 메인 뷰
struct MeetingSummaryView: View {
    @ObservedObject var recorder: AudioRecorder
    @State private var isDroppingFile: Bool = false
    @State private var isRecordingExpanded: Bool = true
    @State private var isPlaybackExpanded: Bool = true
    @State private var isSummaryExpanded: Bool = true

    var body: some View {
        VStack(spacing: DesignToken.sectionSpacing) {
            // 상태 표시
            if recorder.isRecording || recorder.isUploading {
                HStack {
                    Spacer()
                    if recorder.isRecording {
                        StatusBadge(text: "녹음 중", color: .red)
                    } else if recorder.isUploading {
                        HStack(spacing: 12) {
                            StatusBadge(text: "처리 중...", color: DesignToken.accentIndigo)

                            Button {
                                recorder.cancelProcessing()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                    Text("취소")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(DesignToken.errorRed)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer()
                }
                .padding(.top, 4)
            }

            // 에러 메시지
            if let error = recorder.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                        Text(error)
                            .font(.system(size: 11))
                    }
                    .foregroundColor(DesignToken.errorRed)

                    // 마이크 권한 에러일 때 설정 열기 버튼 표시
                    if error.contains("마이크 권한") {
                        Button {
                            recorder.openMicPrivacySettings()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "gear")
                                    .font(.system(size: 11))
                                Text("시스템 설정 열기")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignToken.accentIndigo)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DesignToken.errorRed.opacity(0.06))
                )
                .padding(.horizontal, 16)
            }

            // 녹음 카드
            CardSection(
                title: "녹음",
                icon: "mic.fill",
                isExpanded: $isRecordingExpanded
            ) {
                VStack(spacing: 12) {
                    // 파형 + 드롭존
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(isDroppingFile
                                  ? DesignToken.accentIndigo.opacity(0.04)
                                  : Color(nsColor: .windowBackgroundColor))
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isDroppingFile
                                ? DesignToken.accentIndigo.opacity(0.5)
                                : Color(nsColor: .separatorColor).opacity(0.2),
                                style: StrokeStyle(lineWidth: 1, dash: isDroppingFile ? [] : [5, 3])
                            )

                        VStack(spacing: 6) {
                            WaveformView(level: recorder.currentLevel)
                                .frame(height: 36)
                                .padding(.horizontal, 16)

                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.doc")
                                    .font(.system(size: 11))
                                Text("음성 파일을 여기에 드래그")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(height: 90)
                    .onDrop(of: [UTType.fileURL], isTargeted: $isDroppingFile) { providers in
                        handleFileDrop(providers: providers)
                    }

                    // 녹음 버튼
                    HStack(spacing: 12) {
                        Button {
                            recorder.startRecording()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "mic.fill")
                                    .font(.system(size: 12))
                                Text("녹음 시작")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignToken.accentIndigo)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .disabled(recorder.isRecording || recorder.isUploading)

                        Button {
                            recorder.stopRecording()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 12))
                                Text("녹음 종료")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .disabled(!recorder.isRecording)
                    }
                }
            }
            .padding(.horizontal, 16)

            // 재생 카드
            CardSection(
                title: "녹음 재생",
                icon: "play.circle",
                isExpanded: $isPlaybackExpanded
            ) {
                if recorder.hasRecording {
                    HStack(spacing: 10) {
                        Button {
                            if recorder.isPlaying {
                                recorder.pause()
                            } else {
                                recorder.play()
                            }
                        } label: {
                            Image(systemName: recorder.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(Color(nsColor: .windowBackgroundColor))
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)

                        VStack(spacing: 4) {
                            Slider(
                                value: Binding(
                                    get: { recorder.playbackCurrentTime },
                                    set: { newValue in recorder.seek(to: newValue) }
                                ),
                                in: 0...max(recorder.playbackDuration, 0.1)
                            )
                            .controlSize(.small)
                            .tint(DesignToken.accentIndigo)

                            HStack {
                                Text(formatTime(recorder.playbackCurrentTime))
                                Spacer()
                                Text(formatTime(recorder.playbackDuration))
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                        }
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "speaker.slash")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("녹음 완료 후 재생할 수 있습니다")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 16)

            // 회의록 카드
            CardSection(
                title: "회의록",
                icon: "doc.text",
                isExpanded: $isSummaryExpanded
            ) {
                if let notionURL = recorder.notionPageURL,
                   let url = URL(string: notionURL) {
                    Link(destination: url) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 13))
                            Text("Notion에서 회의록 보기")
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .foregroundColor(DesignToken.accentIndigo)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(DesignToken.accentIndigo.opacity(0.04))
                        )
                    }
                } else if recorder.isUploading {
                    VStack(spacing: 10) {
                        // 프로그레스바
                        ProgressView(value: recorder.processingStage.progress)
                            .progressViewStyle(.linear)
                            .tint(DesignToken.accentIndigo)

                        // 단계 표시 (5단계: 검증 → STT → 화자분리 → 요약 → 등록)
                        HStack(spacing: 0) {
                            ForEach([ProcessingStage.validating, .transcribing, .diarizing, .summarizing, .uploading], id: \.rawValue) { stage in
                                VStack(spacing: 4) {
                                    Circle()
                                        .fill(
                                            recorder.processingStage.rawValue >= stage.rawValue
                                            ? (recorder.processingStage.rawValue > stage.rawValue
                                               ? DesignToken.successGreen
                                               : DesignToken.accentIndigo)
                                            : Color.gray.opacity(0.3)
                                        )
                                        .frame(width: 8, height: 8)
                                    Text(stageLabel(stage))
                                        .font(.system(size: 10))
                                        .foregroundColor(recorder.processingStage.rawValue >= stage.rawValue ? .primary : .secondary)
                                }
                                .frame(maxWidth: .infinity)
                            }
                        }

                        // 현재 상태 텍스트 + 취소 버튼
                        HStack {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(recorder.processingStage.description)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button {
                                recorder.cancelProcessing()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 11))
                                    Text("취소")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundColor(DesignToken.errorRed)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } else if recorder.processingStage == .completed {
                    VStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(DesignToken.successGreen)
                            Text("처리 완료!")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(DesignToken.successGreen)
                        }
                        Text("Notion 링크가 곧 표시됩니다")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.badge.clock")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("완료되면 Notion 링크가 표시됩니다")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
                }
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 8)
        }
        .padding(.vertical, 8)
    }

    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        let recorder = self.recorder

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier,
                                  options: nil) { item, error in
                    if let error = error {
                        print("파일 로드 에러: \(error.localizedDescription)")
                        return
                    }
                    guard let item = item else {
                        print("item 이 nil 입니다.")
                        return
                    }

                    if let url = item as? URL {
                        DispatchQueue.main.async {
                            recorder.processExternalFile(url: url)
                        }
                        return
                    }

                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            recorder.processExternalFile(url: url)
                        }
                        return
                    }

                    print("지원하지 않는 타입: \(type(of: item))")
                }
                return true
            }
        }
        return false
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN else { return "00:00" }
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    private func stageLabel(_ stage: ProcessingStage) -> String {
        switch stage {
        case .validating: return "검증"
        case .transcribing: return "STT"
        case .diarizing: return "화자분리"
        case .summarizing: return "요약"
        case .uploading: return "등록"
        default: return ""
        }
    }
}
