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
    
    // MARK: - OpenAI 설정
    private let openAIAPIKey: String = "openAI KEY값 추가 필요"

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
    
    //  AudioRecorder.swift 내, class AudioRecorder { ... } 안쪽에 추가
    //
    // MARK: - Public API (외부 오디오 파일 처리)
    /// 드래그&드롭 등으로 받은 외부 오디오 파일을 바로 STT/요약 플로우로 처리합니다.
    func processExternalFile(url: URL) {
        // 기존 재생 중지
        audioPlayer?.stop()
        isPlaying = false

        // 드롭된 파일을 현재 녹음 파일로 취급
        recordedFileURL = url

        // 재생 준비 (재생 컨트롤에서 길이 표시용)
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            audioPlayer = player
            audioPlayer?.delegate = self
            playbackDuration = player.duration
            playbackCurrentTime = 0
            hasRecording = true
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "외부 파일 재생 준비 실패: \(error.localizedDescription)"
            }
        }

        // 바로 업로드(STT → n8n) 시작
        uploadAudio(fileURL: url)
    }
    
    // MARK: - 업로드

    private func uploadAudio(fileURL: URL) {
        isUploading = true
        errorMessage = nil
        
        let path = fileURL.path
        var fileSize: Int64 = 0
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            print("⬆️ Transcribe & upload file path: \(path), size: \(fileSize) bytes")
        } catch {
            print("⚠️ Failed to read file attributes for upload: \(error)")
        }
        
        // Whisper 단일 요청으로 보낼 최대 파일 크기(예: 20MB)
        let maxSingleSize: Int64 = 20 * 1024 * 1024
        
        if fileSize > 0 && fileSize > maxSingleSize {
            // 대용량 파일 → 여러 청크로 나누어 순차 STT 후 텍스트를 이어붙임
            print("🔪 Large audio detected (\(fileSize) bytes), using chunked STT")
            transcribeLargeAudio(fileURL: fileURL) { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.isUploading = false
                        self.errorMessage = "STT 실패(대용량): \(error.localizedDescription)"
                    }
                case .success(let transcript):
                    print("📝 STT transcript (chunked) length: \(transcript.count) chars")
                    // 성공 시에는 isUploading 플래그를 n8n 업로드가 끝날 때까지 유지
                    self.sendTranscriptToN8N(transcript: transcript)
                }
            }
        } else {
            // 소용량 파일 → 기존 방식으로 한 번에 STT 호출
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
            
            let fileName = fileURL.lastPathComponent
            
            transcribeWithOpenAI(audioData: audioData, fileName: fileName) { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.isUploading = false
                        self.errorMessage = "STT 실패: \(error.localizedDescription)"
                    }
                case .success(let transcript):
                    print("📝 STT transcript length: \(transcript.count) chars")
                    // 성공 시에는 isUploading 플래그를 n8n 업로드가 끝날 때까지 유지
                    self.sendTranscriptToN8N(transcript: transcript)
                }
            }
        }
    }
    
    // MARK: - OpenAI Whisper STT 호출
    
    private struct OpenAITranscriptionResponse: Decodable {
        let text: String
    }
    
    /// OpenAI Whisper Audio Transcriptions API를 호출해 STT 텍스트를 가져옵니다.
    private func transcribeWithOpenAI(audioData: Data, fileName: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://api.openai.com/v1/audio/transcriptions") else {
            completion(.failure(NSError(domain: "AudioRecorder", code: -1, userInfo: [NSLocalizedDescriptionKey: "잘못된 OpenAI STT URL"])))
            return
        }
        
        let boundary = "Boundary-\(UUID().uuidString)"
        let lineBreak = "\r\n"
        
        // 15분 타임아웃 설정
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 900      // 15분
        config.timeoutIntervalForResource = 900     // 15분
        let session = URLSession(configuration: config)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(openAIAPIKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 900               // 요청 자체에도 15분 타임아웃
        
        var body = Data()
        
        // model 필드
        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append("whisper-1\(lineBreak)".data(using: .utf8)!)
        
        // (선택) 언어 명시 - 한국어 기준
        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append("ko\(lineBreak)".data(using: .utf8)!)
        
        // file 필드
        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append(audioData)
        body.append(lineBreak.data(using: .utf8)!)
        
        // 끝
        body.append("--\(boundary)--\(lineBreak)".data(using: .utf8)!)
        
        let task = session.uploadTask(with: request, from: body) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "AudioRecorder", code: -2, userInfo: [NSLocalizedDescriptionKey: "잘못된 OpenAI 응답 형식"])))
                return
            }
            
            guard (200..<300).contains(httpResponse.statusCode) else {
                let msg = "OpenAI STT 응답 코드: \(httpResponse.statusCode)"
                completion(.failure(NSError(domain: "AudioRecorder", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "AudioRecorder", code: -3, userInfo: [NSLocalizedDescriptionKey: "OpenAI STT 응답 데이터 없음"])))
                return
            }
            
            if let debugText = String(data: data, encoding: .utf8) {
                print("📩 OpenAI STT raw response:\n\(debugText)")
            }
            
            do {
                let decoded = try JSONDecoder().decode(OpenAITranscriptionResponse.self, from: data)
                completion(.success(decoded.text))
            } catch {
                completion(.failure(error))
            }
        }
        
        task.resume()
    }
    
    // n8n 응답 파싱용 구조체 (요약 결과 URL 포함)
    private struct N8NSummaryResponse: Decodable {
        let summaryUrl: String?
        let url: String?
    }
    
    // MARK: - n8n 워크플로우 호출 (STT 텍스트 전달)
    
    private func sendTranscriptToN8N(transcript: String) {
        guard let url = URL(string: "https://www.linkly.kr/n8n/webhook/098e8967-d9fc-4cbc-affa-92efff9fcff9") else {
            DispatchQueue.main.async {
                self.isUploading = false
                self.errorMessage = "잘못된 n8n API URL"
            }
            return
        }
        
        // 15분 타임아웃 설정
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 900      // 15분
        config.timeoutIntervalForResource = 900     // 15분
        let session = URLSession(configuration: config)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 900               // 요청 자체에도 15분 타임아웃
        
        // n8n 쪽에서 transcript 필드를 기준으로 처리하도록 가정
        let payload: [String: Any] = [
            "transcript": transcript
        ]
        
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [])
            request.httpBody = data
        } catch {
            DispatchQueue.main.async {
                self.isUploading = false
                self.errorMessage = "요청 JSON 생성 실패: \(error.localizedDescription)"
            }
            return
        }
        
        let task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error as NSError? {
                print("❌ n8n upload error: \(error.domain) \(error.code) \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isUploading = false
                    self.errorMessage = "업로드 실패: \(error.localizedDescription) (code: \(error.code))"
                }
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    self.isUploading = false
                    self.errorMessage = "잘못된 n8n 응답 형식"
                }
                return
            }
            
            print("📡 n8n HTTP status code: \(httpResponse.statusCode)")
            print("📡 n8n Response headers: \(httpResponse.allHeaderFields)")
            
            guard (200..<300).contains(httpResponse.statusCode) else {
                DispatchQueue.main.async {
                    self.isUploading = false
                    self.errorMessage = "서버 응답 코드: \(httpResponse.statusCode)"
                }
                return
            }
            
            // 응답 바디 디버그용 출력 및 URL 파싱
            var parsedSummaryURL: URL?
            if let data = data {
                if let text = String(data: data, encoding: .utf8) {
                    print("📩 n8n raw response body:\n\(text)")
                } else {
                    print("📩 n8n raw response body length: \(data.count) bytes")
                }
                
                // n8n 응답 JSON에서 summaryUrl 또는 url 필드 파싱
                do {
                    let decoded = try JSONDecoder().decode(N8NSummaryResponse.self, from: data)
                    if let urlString = decoded.summaryUrl ?? decoded.url,
                       let url = URL(string: urlString) {
                        parsedSummaryURL = url
                    }
                } catch {
                    print("⚠️ n8n 응답 JSON 디코딩 실패: \(error.localizedDescription)")
                }
            }
            
            DispatchQueue.main.async {
                self.isUploading = false
                // n8n이 반환한 URL이 있다면 요약 결과 URL로 반영
                if let url = parsedSummaryURL {
                    self.summaryURL = url
                }
            }
        }
        
        task.resume()
    }
    /// 대용량 오디오 파일을 일정 길이(예: 10분) 단위로 나누어 순차적으로 STT 수행 후 하나의 텍스트로 합칩니다.
    private func transcribeLargeAudio(fileURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        let asset = AVURLAsset(url: fileURL)
        let durationSeconds = CMTimeGetSeconds(asset.duration)
        
        guard durationSeconds.isFinite && durationSeconds > 0 else {
            completion(.failure(NSError(domain: "AudioRecorder",
                                        code: -20,
                                        userInfo: [NSLocalizedDescriptionKey: "오디오 duration 정보를 가져오지 못했습니다."])))
            return
        }
        
        // 청크 길이(초) - 10분 단위
        let chunkDuration: Double = 600.0
        let chunkCount = max(1, Int(ceil(durationSeconds / chunkDuration)))
        
        print("🔪 Splitting audio into \(chunkCount) chunks (duration: \(durationSeconds) seconds)")
        
        var transcripts: [String] = Array(repeating: "", count: chunkCount)
        var currentIndex = 0
        
        func processNextChunk() {
            if currentIndex >= chunkCount {
                // 모든 청크 처리 완료 → 텍스트 합치기
                let merged = transcripts.joined(separator: " ")
                completion(.success(merged))
                return
            }
            
            let startTime = Double(currentIndex) * chunkDuration
            let remaining = durationSeconds - startTime
            let thisDuration = min(chunkDuration, remaining)
            
            print("🔪 Exporting chunk \(currentIndex + 1)/\(chunkCount) [start=\(startTime), duration=\(thisDuration)]")
            
            exportAudioChunk(asset: asset, startTime: startTime, duration: thisDuration) { [weak self] exportResult in
                guard let self = self else { return }
                
                switch exportResult {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let chunkURL):
                    do {
                        let chunkData = try Data(contentsOf: chunkURL)
                        let chunkFileName = "chunk-\(currentIndex)-\(fileURL.lastPathComponent)"
                        
                        self.transcribeWithOpenAI(audioData: chunkData, fileName: chunkFileName) { sttResult in
                            // 사용 완료 후 청크 파일은 삭제 시도
                            try? FileManager.default.removeItem(at: chunkURL)
                            
                            switch sttResult {
                            case .failure(let error):
                                completion(.failure(error))
                            case .success(let text):
                                transcripts[currentIndex] = text
                                currentIndex += 1
                                processNextChunk()
                            }
                        }
                    } catch {
                        completion(.failure(error))
                    }
                }
            }
        }
        
        processNextChunk()
    }

    /// AVAsset에서 지정한 구간(startTime, duration)을 m4a 파일로 내보냅니다.
    private func exportAudioChunk(asset: AVAsset,
                                  startTime: Double,
                                  duration: Double,
                                  completion: @escaping (Result<URL, Error>) -> Void) {
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            completion(.failure(NSError(domain: "AudioRecorder",
                                        code: -21,
                                        userInfo: [NSLocalizedDescriptionKey: "AVAssetExportSession 생성 실패"])))
            return
        }
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chunk-\(UUID().uuidString).m4a")
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        
        let timescale = asset.duration.timescale
        let start = CMTime(seconds: startTime, preferredTimescale: timescale)
        let dur = CMTime(seconds: duration, preferredTimescale: timescale)
        exportSession.timeRange = CMTimeRange(start: start, duration: dur)
        
        exportSession.exportAsynchronously {
            switch exportSession.status {
            case .completed:
                completion(.success(outputURL))
            case .failed, .cancelled:
                let error = exportSession.error ?? NSError(domain: "AudioRecorder",
                                                           code: -22,
                                                           userInfo: [NSLocalizedDescriptionKey: "오디오 청크 내보내기 실패"])
                completion(.failure(error))
            default:
                break
            }
        }
    }
}
