//
//  ContentView.swift
//  MeetingSummaryApp
//
//  Created by 최영기 on 11/23/25.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var recorder = AudioRecorder()
    @State private var isDroppingFile: Bool = false

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
                    .strokeBorder(isDroppingFile ? Color.blue.opacity(0.7) : Color.gray.opacity(0.4), lineWidth: isDroppingFile ? 2 : 1)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill((isDroppingFile ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1)))
                    )
                
                VStack(spacing: 8) {
                    WaveformView(level: recorder.currentLevel)
                        .padding(12)
                    
                    Text("여기에 음성 파일(m4a 등)을 드래그하면\n녹음 없이 바로 STT/요약을 진행합니다.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
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
        .onDrop(of: [UTType.fileURL], isTargeted: $isDroppingFile) { providers in
            handleFileDrop(providers: providers)
        }
        .frame(width: 480, height: 420)
        .padding()
    }

    // 드래그&드롭된 파일 처리
    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        // recorder를 먼저 로컬 상수로 캡처해두면
        // 뷰(struct)의 self를 직접 캡처하지 않아도 되어서 더 안전함
        let recorder = self.recorder

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier,
                                  options: nil) { item, error in
                    if let error = error {
                        print("❌ 파일 로드 에러: \(error.localizedDescription)")
                        return
                    }
                    guard let item = item else {
                        print("❌ item 이 nil 입니다.")
                        return
                    }

                    // 1) URL 타입으로 먼저 시도
                    if let url = item as? URL {
                        DispatchQueue.main.async {
                            recorder.processExternalFile(url: url)
                        }
                        return
                    }

                    // 2) Data → URL 변환 시도
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil) {
                        DispatchQueue.main.async {
                            recorder.processExternalFile(url: url)
                        }
                        return
                    }

                    print("❌ 지원하지 않는 타입: \(type(of: item))")
                }
                return true
            }
        }
        return false
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
