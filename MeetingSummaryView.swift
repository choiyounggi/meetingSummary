//
//  MeetingSummaryView.swift
//  MeetingSummaryApp
//
//  Created by 최영기 on 12/12/25.
//

import SwiftUI
import UniformTypeIdentifiers

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
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
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
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if isExpanded?.wrappedValue != false {
                Divider()
                    .padding(.horizontal, 14)

                content()
                    .padding(14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
        )
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
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(color.opacity(0.1))
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
        VStack(spacing: 10) {
            // 상태 표시
            if recorder.isRecording || recorder.isUploading {
                HStack {
                    Spacer()
                    if recorder.isRecording {
                        StatusBadge(text: "녹음 중", color: .red)
                    } else if recorder.isUploading {
                        StatusBadge(text: "처리 중...", color: .blue)
                    }
                    Spacer()
                }
                .padding(.top, 4)
            }

            // 에러 메시지
            if let error = recorder.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                    Text(error)
                        .font(.system(size: 11))
                }
                .foregroundColor(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.08))
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
                                  ? Color.accentColor.opacity(0.06)
                                  : Color(nsColor: .windowBackgroundColor))
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isDroppingFile
                                ? Color.accentColor.opacity(0.5)
                                : Color(nsColor: .separatorColor).opacity(0.3),
                                style: StrokeStyle(lineWidth: 1, dash: isDroppingFile ? [] : [5, 3])
                            )

                        VStack(spacing: 6) {
                            WaveformView(level: recorder.currentLevel)
                                .frame(height: 36)
                                .padding(.horizontal, 16)

                            Text("음성 파일(m4a 등)을 드래그하여 바로 처리")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(height: 80)
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
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(nsColor: NSColor(red: 0.25, green: 0.25, blue: 0.3, alpha: 1.0)))
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
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.bordered)
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
                                .font(.system(size: 13))
                                .foregroundColor(.primary)
                                .frame(width: 30, height: 30)
                                .background(
                                    Circle()
                                        .fill(Color(nsColor: .windowBackgroundColor))
                                )
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 0.5)
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
                        .padding(.vertical, 4)
                    }
                } else if recorder.isUploading {
                    VStack(spacing: 10) {
                        // 프로그레스바
                        ProgressView(value: recorder.processingStage.progress)
                            .progressViewStyle(.linear)
                            .tint(.blue)

                        // 단계 표시
                        HStack(spacing: 0) {
                            ForEach([ProcessingStage.transcribing, .summarizing, .uploading], id: \.rawValue) { stage in
                                VStack(spacing: 4) {
                                    Circle()
                                        .fill(recorder.processingStage.rawValue >= stage.rawValue ? Color.blue : Color.gray.opacity(0.3))
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
                                .foregroundColor(.red)
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
                                .foregroundColor(.green)
                            Text("처리 완료!")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.green)
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
        case .transcribing: return "STT"
        case .summarizing: return "요약"
        case .uploading: return "등록"
        default: return ""
        }
    }
}
