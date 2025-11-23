//
//  ContentView.swift
//  MeetingSummaryApp
//
//  Created by 최영기 on 11/23/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var recorder = AudioRecorder()

    var body: some View {
        VStack(spacing: 16) {
            Text("회의 녹음 & 요약")
                .font(.title2)
                .padding(.top, 12)

            // 상태 표시
            if recorder.isRecording {
                Text("녹음 중...")
                    .foregroundColor(.red)
                    .font(.headline)
            } else if recorder.isUploading {
                Text("업로드 및 요약 생성 중...")
                    .foregroundColor(.blue)
            }

            if let error = recorder.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }

            // 파형 뷰
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.gray.opacity(0.4), lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.gray.opacity(0.1))
                    )

                WaveformView(level: recorder.currentLevel)
                    .padding(12)
            }
            .frame(height: 120)
            .padding(.horizontal, 16)

            // ✅ 재생 컨트롤 (녹음이 하나라도 있을 때만 표시)
            if recorder.hasRecording {
                VStack(alignment: .leading, spacing: 8) {
                    Text("녹음 재생")
                        .font(.headline)

                    HStack {
                        Button(action: {
                            if recorder.isPlaying {
                                recorder.pause()
                            } else {
                                recorder.play()
                            }
                        }) {
                            Image(systemName: recorder.isPlaying ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(.bordered)

                        // 타임라인 슬라이더
                        Slider(
                            value: Binding(
                                get: { recorder.playbackCurrentTime },
                                set: { newValue in
                                    recorder.seek(to: newValue)
                                }
                            ),
                            in: 0...max(recorder.playbackDuration, 0.1)
                        )

                        // 현재 / 전체 시간 표시
                        Text("\(formatTime(recorder.playbackCurrentTime)) / \(formatTime(recorder.playbackDuration))")
                            .font(.caption.monospacedDigit())
                            .frame(width: 110, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 16)
            } else {
                Text("녹음 종료 후 이곳에서 음성을 다시 재생할 수 있습니다.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
            }

            // 녹음 버튼
            HStack(spacing: 24) {
                Button(action: {
                    recorder.startRecording()
                }) {
                    Label("녹음 시작", systemImage: "mic.fill")
                }
                .disabled(recorder.isRecording || recorder.isUploading)

                Button(action: {
                    recorder.stopRecording()
                }) {
                    Label("녹음 종료", systemImage: "stop.fill")
                }
                .disabled(!recorder.isRecording)
            }
            .buttonStyle(.borderedProminent)

            Divider()
                .padding(.horizontal, 16)

            // 요약 URL 영역
            VStack(alignment: .leading, spacing: 8) {
                Text("회의 요약 결과")
                    .font(.headline)

                if let url = recorder.summaryURL {
                    Link(destination: url) {
                        Text(url.absoluteString)
                            .font(.footnote)
                            .foregroundColor(.blue)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                } else {
                    Text("녹음을 종료하면 이곳에 요약 URL이 표시됩니다.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: 480, height: 420)
        .padding()
    }

    // 시간 포맷터 (초 → mm:ss)
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN else { return "00:00" }
        let total = Int(seconds.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
