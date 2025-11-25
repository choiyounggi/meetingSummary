//
//  AudioRecorder.swift
//  MeetingSummaryApp
//
//  Created by 최영기 on 11/23/25.
//

import Foundation
import AVFoundation
import Combine
import CoreGraphics
import SwiftUI
#if os(macOS)
import AppKit
#endif

class AudioRecorder: NSObject, ObservableObject, AVAudioPlayerDelegate {

    // MARK: - Recording 상태
    @Published var isRecording: Bool = false
    @Published var currentLevel: CGFloat = 0.0      // 파동 0.0 ~ 1.0
    @Published var isUploading: Bool = false
    @Published var summaryURL: URL?
    @Published var errorMessage: String?

    // MARK: - Playback 상태
    @Published var hasRecording: Bool = false       // 녹음 파일 존재 여부
    @Published var isPlaying: Bool = false
    @Published var playbackDuration: Double = 0.0   // 전체 길이 (초)
    @Published var playbackCurrentTime: Double = 0.0 // 현재 재생 위치 (초)

    // MARK: - 내부 필드
    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var meterTimer: Timer?
    private var playbackTimer: Timer?
    private var recordedFileURL: URL?

    // MARK: - Public API (녹음)

    func startRecording() {
        // 1) 먼저 마이크 권한 체크
        checkMicPermission { [weak self] granted in
            guard let self = self, granted else { return }

            // 2) 권한이 허용된 경우에만 실제 녹음 시작 로직 수행
            // 업로드/재생 관련 상태 초기화
            self.summaryURL = nil
            self.errorMessage = nil
            self.stopPlaybackIfNeeded()
            self.hasRecording = false
            self.playbackDuration = 0
            self.playbackCurrentTime = 0

            let fileName = "meeting-\(UUID().uuidString).m4a"
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent(fileName)
            self.recordedFileURL = fileURL

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            do {
                self.audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
                self.audioRecorder?.isMeteringEnabled = true
                self.audioRecorder?.prepareToRecord()
                self.audioRecorder?.record()

                self.isRecording = true
                self.startMetering()
            } catch {
                self.errorMessage = "녹음 시작 실패: \(error.localizedDescription)"
                self.isRecording = false
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }

        audioRecorder?.stop()
        audioRecorder = nil
        isRecording = false

        stopMetering()
        currentLevel = 0.0

        guard let fileURL = recordedFileURL else {
            errorMessage = "녹음 파일 URL이 없습니다."
            return
        }

        // 녹음 파일 크기/존재 확인
        let path = fileURL.path
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            let fileSize = (attrs[.size] as? NSNumber)?.intValue ?? 0
            print("🎙 Recorded file: \(path), size: \(fileSize) bytes")

            if fileSize == 0 {
                DispatchQueue.main.async {
                    self.errorMessage = "녹음 파일 크기가 0입니다. 실제 녹음이 안 되었을 수 있어요."
                }
            }
        } catch {
            print("⚠️ Failed to read file attributes: \(error)")
            DispatchQueue.main.async {
                self.errorMessage = "녹음 파일 정보를 읽지 못했습니다: \(error.localizedDescription)"
            }
        }

        // ✅ 재생용 준비
        preparePlayback(fileURL: fileURL)

        // ✅ 업로드
        uploadAudio(fileURL: fileURL)
    }

    // MARK: - Metering (파동용)

    private func startMetering() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.updateMeter()
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func updateMeter() {
        guard let recorder = audioRecorder, recorder.isRecording else { return }

        recorder.updateMeters()
        let dB = recorder.averagePower(forChannel: 0)
        let minDb: Float = -60.0
        let level: CGFloat

        if dB < minDb {
            level = 0.0
        } else {
            let normalized = (dB - minDb) / -minDb
            level = CGFloat(normalized)
        }

        DispatchQueue.main.async {
            withAnimation(.linear(duration: 0.05)) {
                self.currentLevel = level
            }
        }
    }

    // MARK: - Playback 준비/제어

    private func preparePlayback(fileURL: URL) {
        do {
            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.delegate = self
            player.prepareToPlay()

            // ✅ 볼륨 최대로 (0.0~1.0)
            player.volume = 1.0

            audioPlayer = player

            DispatchQueue.main.async {
                self.playbackDuration = player.duration
                self.playbackCurrentTime = 0
                self.hasRecording = true
                self.isPlaying = false
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "재생 준비 실패: \(error.localizedDescription)"
            }
        }
    }

    func play() {
        guard let player = audioPlayer, hasRecording else { return }
        if !player.isPlaying {
            player.play()
            isPlaying = true
            startPlaybackTimer()
        }
    }

    func pause() {
        guard let player = audioPlayer else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            stopPlaybackTimer()
        }
    }

    func seek(to time: Double) {
        guard let player = audioPlayer, hasRecording else { return }
        let clamped = max(0, min(time, player.duration))
        player.currentTime = clamped
        playbackCurrentTime = clamped
    }

    private func startPlaybackTimer() {
        stopPlaybackTimer()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer else { return }
            DispatchQueue.main.async {
                self.playbackCurrentTime = player.currentTime
                if !player.isPlaying {
                    self.isPlaying = false
                    self.stopPlaybackTimer()
                }
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    private func stopPlaybackIfNeeded() {
        audioPlayer?.stop()
        isPlaying = false
        stopPlaybackTimer()
        playbackCurrentTime = 0
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.isPlaying = false
            self.playbackCurrentTime = self.playbackDuration
        }
        stopPlaybackTimer()
    }

    // MARK: - 권한 체크

    private func checkMicPermission(completion: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .authorized:
            // 이미 허용
            completion(true)

        case .notDetermined:
            // 처음 요청 → 시스템 권한 팝업
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if !granted {
#if os(macOS)
                        self.errorMessage = "마이크 권한이 거부되었습니다. 시스템 설정 > 개인정보 보호 및 보안 > 마이크에서 이 앱을 허용해주세요. 필요 시 아래 버튼으로 설정을 여세요."
#else
                        self.errorMessage = "마이크 권한이 거부되었습니다. 설정 > 개인정보 보호 및 보안 > 마이크에서 이 앱을 허용해주세요."
#endif
                    }
                    completion(granted)
                }
            }

        case .denied, .restricted:
            // 이전에 거부했거나 제한된 상태
            DispatchQueue.main.async {
#if os(macOS)
                self.errorMessage = "마이크 권한이 꺼져 있습니다. 시스템 설정 > 개인정보 보호 및 보안 > 마이크에서 이 앱을 허용해주세요. 필요 시 아래 버튼으로 설정을 여세요."
#else
                self.errorMessage = "마이크 권한이 꺼져 있습니다. 설정 > 개인정보 보호 및 보안 > 마이크에서 이 앱을 허용해주세요."
#endif
            }
            completion(false)

        @unknown default:
            completion(false)
        }
    }
    
    #if os(macOS)
    @MainActor
    func openMicPrivacySettings() {
        // Try to open the Privacy Microphone pane directly
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }
    #endif

    // MARK: - 업로드

    private struct SummaryResponse: Decodable {
        let summaryUrl: String
        
        init(from decoder: Decoder) throws {
            // 1) 먼저 단일 값 컨테이너를 시도
            let single = try decoder.singleValueContainer()
            
            // 케이스 A: {"summaryUrl": "..."} 형태
            if let dict = try? single.decode([String: String].self),
               let value = dict["summaryUrl"] {
                self.summaryUrl = value
                return
            }
            
            // 케이스 B: "https://..." 같은 단일 문자열 형태
            if let str = try? single.decode(String.self) {
                self.summaryUrl = str
                return
            }
            
            // 둘 다 아니면 JSON 포맷이 예상과 다름
            throw DecodingError.dataCorruptedError(
                in: single,
                debugDescription: "Expected either {\"summaryUrl\": \"...\"} or a plain string URL."
            )
        }
    }

    private func uploadAudio(fileURL: URL) {
        isUploading = true
        errorMessage = nil
        
        guard let url = URL(string: "https://www.linkly.kr/n8n/webhook/098e8967-d9fc-4cbc-affa-92efff9fcff9") else {
            self.errorMessage = "잘못된 API URL"
            self.isUploading = false
            return
        }

        print("⬆️ Uploading to: \(url.absoluteString)")
        print("⬆️ Upload file path: \(fileURL.path)")

        // 1) 파일 데이터 읽기
        let audioData: Data
        do {
            audioData = try Data(contentsOf: fileURL)
        } catch {
            DispatchQueue.main.async {
                self.isUploading = false
                self.errorMessage = "녹음 파일 읽기 실패: \(error.localizedDescription)"
            }
            return
        }

        // 2) multipart/form-data 바운더리 생성
        let boundary = "Boundary-\(UUID().uuidString)"

        // 🔹 2-1) 타임아웃 10분 설정된 URLSessionConfiguration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 600      // 개별 요청 타임아웃 (10분)
        config.timeoutIntervalForResource = 600     // 전체 리소스 다운로드 타임아웃 (10분)
        let session = URLSession(configuration: config)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 600               // 🔹 request 자체에도 10분 타임아웃 설정

        // 3) 바디 구성
        var body = Data()
        let lineBreak = "\r\n"
        let fileName = fileURL.lastPathComponent          // 예: meeting-XXXX.m4a

        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append(audioData)
        body.append(lineBreak.data(using: .utf8)!)
        body.append("--\(boundary)--\(lineBreak)".data(using: .utf8)!)

        // 4) 업로드
        let task = session.uploadTask(with: request, from: body) { [weak self] data, response, error in
            guard let self = self else { return }

            DispatchQueue.main.async {
                self.isUploading = false
            }

            if let error = error as NSError? {
                print("❌ Upload error domain: \(error.domain), code: \(error.code), desc: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = "업로드 실패: \(error.localizedDescription) (code: \(error.code))"
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    self.errorMessage = "잘못된 응답 형식"
                }
                return
            }

            print("📡 HTTP status code: \(httpResponse.statusCode)")
            print("📡 Response headers: \(httpResponse.allHeaderFields)")
            print("📡 Response: \(httpResponse)")

            guard (200..<300).contains(httpResponse.statusCode) else {
                DispatchQueue.main.async {
                    self.errorMessage = "서버 응답 코드: \(httpResponse.statusCode)"
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    self.errorMessage = "응답 데이터 없음"
                }
                return
            }

            // 🔹 JSON 파싱 전에 raw response를 먼저 로그로 찍기
            if let responseText = String(data: data, encoding: .utf8) {
                print("📩 Raw response body:\n\(responseText)")
            } else {
                print("📩 Raw response body (non-UTF8, length: \(data.count) bytes)")
            }

            do {
                let decoded = try JSONDecoder().decode(SummaryResponse.self, from: data)
                if let url = URL(string: decoded.summaryUrl) {
                    DispatchQueue.main.async {
                        self.summaryURL = url
                    }
                } else {
                    DispatchQueue.main.async {
                        self.errorMessage = "요약 URL 파싱 실패"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "JSON 파싱 실패: \(error.localizedDescription)"
                }
            }
        }

        task.resume()
    }
}

