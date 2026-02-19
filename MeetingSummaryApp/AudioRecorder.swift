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

// MARK: - 처리 단계 enum
enum ProcessingStage: Int, CaseIterable {
    case idle = 0
    case validating = 1      // API 토큰 검증 중
    case transcribing = 2    // STT 변환 중
    case summarizing = 3     // 요약 중
    case uploading = 4       // Notion 등록 중
    case completed = 5       // 완료

    var description: String {
        switch self {
        case .idle: return ""
        case .validating: return "API 토큰 검증 중..."
        case .transcribing: return "음성을 텍스트로 변환 중..."
        case .summarizing: return "회의 내용 요약 중..."
        case .uploading: return "Notion에 등록 중..."
        case .completed: return "완료"
        }
    }

    var progress: Double {
        switch self {
        case .idle: return 0.0
        case .validating: return 0.05
        case .transcribing: return 0.30
        case .summarizing: return 0.60
        case .uploading: return 0.85
        case .completed: return 1.0
        }
    }
}

class AudioRecorder: NSObject, ObservableObject, AVAudioPlayerDelegate {

    // MARK: - Recording 상태
    @Published var isRecording: Bool = false
    @Published var currentLevel: CGFloat = 0.0      // 파동 0.0 ~ 1.0
    @Published var isUploading: Bool = false
    @Published var processingStage: ProcessingStage = .idle
    @Published var transcriptText: String?
    @Published var summaryText: String?
    @Published var notionPageURL: String?
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
    private var currentTask: URLSessionTask?
    private var isCancelled: Bool = false

    // MARK: - Public API (취소)

    func cancelProcessing() {
        isCancelled = true
        currentTask?.cancel()
        currentTask = nil

        DispatchQueue.main.async {
            self.isUploading = false
            self.processingStage = .idle
            self.errorMessage = "처리가 취소되었습니다."
        }
    }

    // MARK: - Public API (녹음)

    func startRecording() {
        // 1) 상태 초기화
        transcriptText = nil
        summaryText = nil
        notionPageURL = nil
        errorMessage = nil
        processingStage = .validating
        isUploading = true

        // 2) 토큰 검증 먼저 수행
        validateAllTokens { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isUploading = false
                    self.processingStage = .idle
                    self.errorMessage = error.localizedDescription
                }
            case .success:
                DispatchQueue.main.async {
                    self.isUploading = false
                    self.processingStage = .idle
                }
                // 3) 검증 통과 후 마이크 권한 체크 → 녹음 시작
                self.checkMicPermission { [weak self] granted in
                    guard let self = self, granted else { return }
                    self.beginRecording()
                }
            }
        }
    }

    /// 검증/권한 체크 완료 후 실제 녹음을 시작합니다.
    private func beginRecording() {
        stopPlaybackIfNeeded()
        hasRecording = false
        playbackDuration = 0
        playbackCurrentTime = 0

        let fileName = "meeting-\(UUID().uuidString).m4a"
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(fileName)
        recordedFileURL = fileURL

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            audioRecorder?.record()

            isRecording = true
            startMetering()
        } catch {
            errorMessage = "녹음 시작 실패: \(error.localizedDescription)"
            isRecording = false
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
            completion(true)

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    if !granted {
#if os(macOS)
                        self.errorMessage = "마이크 권한이 거부되었습니다. 시스템 설정에서 이 앱의 마이크 접근을 허용해주세요."
#else
                        self.errorMessage = "마이크 권한이 거부되었습니다. 설정 > 개인정보 보호 및 보안 > 마이크에서 이 앱을 허용해주세요."
#endif
                    }
                    completion(granted)
                }
            }

        case .denied, .restricted:
            DispatchQueue.main.async {
#if os(macOS)
                self.errorMessage = "마이크 권한이 꺼져 있습니다. 시스템 설정에서 이 앱의 마이크 접근을 허용해주세요."
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
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }
    #endif
    
    // MARK: - Public API (외부 오디오 파일 처리)
    func processExternalFile(url: URL) {
        audioPlayer?.stop()
        isPlaying = false

        recordedFileURL = url
        transcriptText = nil
        summaryText = nil
        notionPageURL = nil
        errorMessage = nil
        processingStage = .validating
        isUploading = true

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

        // 토큰 검증 후 업로드 진행
        validateAllTokens { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isUploading = false
                    self.processingStage = .idle
                    self.errorMessage = error.localizedDescription
                }
            case .success:
                self.uploadAudio(fileURL: url)
            }
        }
    }
    
    // MARK: - API 토큰 검증

    /// 모든 필수 API 토큰의 존재 여부와 유효성을 병렬로 검증합니다.
    private func validateAllTokens(completion: @escaping (Result<Void, Error>) -> Void) {
        let settings = SettingsManager.shared

        // 1) 토큰 존재 여부 먼저 확인
        var missingKeys: [String] = []
        if settings.openAIKey.isEmpty { missingKeys.append("OpenAI") }
        if settings.anthropicKey.isEmpty { missingKeys.append("Anthropic") }
        if settings.notionKey.isEmpty { missingKeys.append("Notion") }
        if settings.githubToken.isEmpty { missingKeys.append("GitHub") }

        if !missingKeys.isEmpty {
            let msg = "다음 API 키가 설정되지 않았습니다: \(missingKeys.joined(separator: ", "))\n설정 탭에서 입력해주세요."
            completion(.failure(NSError(domain: "AudioRecorder", code: -50, userInfo: [NSLocalizedDescriptionKey: msg])))
            return
        }

        // 2) 유효성 병렬 검증
        let group = DispatchGroup()
        var errors: [String] = []
        let lock = NSLock()

        // OpenAI
        group.enter()
        validateOpenAIToken(settings.openAIKey) { valid in
            if !valid {
                lock.lock()
                errors.append("OpenAI")
                lock.unlock()
            }
            group.leave()
        }

        // Anthropic
        group.enter()
        validateAnthropicToken(settings.anthropicKey) { valid in
            if !valid {
                lock.lock()
                errors.append("Anthropic")
                lock.unlock()
            }
            group.leave()
        }

        // Notion
        group.enter()
        validateNotionToken(settings.notionKey) { valid in
            if !valid {
                lock.lock()
                errors.append("Notion")
                lock.unlock()
            }
            group.leave()
        }

        // GitHub
        group.enter()
        validateGitHubToken(settings.githubToken) { valid in
            if !valid {
                lock.lock()
                errors.append("GitHub")
                lock.unlock()
            }
            group.leave()
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            lock.lock()
            let failedKeys = errors
            lock.unlock()

            if failedKeys.isEmpty {
                print("✅ 모든 API 토큰 검증 완료")
                completion(.success(()))
            } else {
                let msg = "다음 API 키가 유효하지 않습니다: \(failedKeys.joined(separator: ", "))\n설정 탭에서 올바른 키를 입력해주세요."
                completion(.failure(NSError(domain: "AudioRecorder", code: -51, userInfo: [NSLocalizedDescriptionKey: msg])))
            }
        }
    }

    private func validateOpenAIToken(_ token: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { _, response, error in
            guard error == nil, let http = response as? HTTPURLResponse else {
                completion(false)
                return
            }
            let valid = (200..<300).contains(http.statusCode)
            print(valid ? "✅ OpenAI 토큰 유효" : "❌ OpenAI 토큰 무효 (HTTP \(http.statusCode))")
            completion(valid)
        }.resume()
    }

    private func validateAnthropicToken(_ token: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            completion(false)
            return
        }
        // 최소 요청으로 토큰 유효성만 확인 (max_tokens=1)
        let payload: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 10
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { _, response, error in
            guard error == nil, let http = response as? HTTPURLResponse else {
                completion(false)
                return
            }
            // 200 = 정상 응답, 401/403 = 토큰 무효
            let valid = (200..<300).contains(http.statusCode)
            print(valid ? "✅ Anthropic 토큰 유효" : "❌ Anthropic 토큰 무효 (HTTP \(http.statusCode))")
            completion(valid)
        }.resume()
    }

    private func validateNotionToken(_ token: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://api.notion.com/v1/users/me") else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { _, response, error in
            guard error == nil, let http = response as? HTTPURLResponse else {
                completion(false)
                return
            }
            let valid = (200..<300).contains(http.statusCode)
            print(valid ? "✅ Notion 토큰 유효" : "❌ Notion 토큰 무효 (HTTP \(http.statusCode))")
            completion(valid)
        }.resume()
    }

    private func validateGitHubToken(_ token: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://api.github.com/user") else {
            completion(false)
            return
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { _, response, error in
            guard error == nil, let http = response as? HTTPURLResponse else {
                completion(false)
                return
            }
            let valid = (200..<300).contains(http.statusCode)
            print(valid ? "✅ GitHub 토큰 유효" : "❌ GitHub 토큰 무효 (HTTP \(http.statusCode))")
            completion(valid)
        }.resume()
    }

    // MARK: - 업로드

    /// 토큰 검증이 완료된 후 호출됩니다.
    private func uploadAudio(fileURL: URL) {
        DispatchQueue.main.async {
            self.isUploading = true
            self.isCancelled = false
            self.processingStage = .transcribing
            self.errorMessage = nil
            self.transcriptText = nil
            self.summaryText = nil
            self.notionPageURL = nil
        }
        startTranscription(fileURL: fileURL)
    }

    private func startTranscription(fileURL: URL) {
        let path = fileURL.path
        var fileSize: Int64 = 0
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            print("⬆️ Transcribe & upload file path: \(path), size: \(fileSize) bytes")
        } catch {
            print("⚠️ Failed to read file attributes for upload: \(error)")
        }
        
        let maxSingleSize: Int64 = 20 * 1024 * 1024
        
        if fileSize > 0 && fileSize > maxSingleSize {
            print("🔪 Large audio detected (\(fileSize) bytes), using chunked STT")
            transcribeLargeAudio(fileURL: fileURL) { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.isUploading = false
                        self.processingStage = .idle
                        self.errorMessage = "STT 실패(대용량): \(error.localizedDescription)"
                    }
                case .success(let transcript):
                    print("📝 STT transcript (chunked) length: \(transcript.count) chars")
                    self.handleTranscript(transcript)
                }
            }
        } else {
            let audioData: Data
            do {
                audioData = try Data(contentsOf: fileURL)
            } catch {
                DispatchQueue.main.async {
                    self.isUploading = false
                    self.processingStage = .idle
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
                        self.processingStage = .idle
                        self.errorMessage = "STT 실패: \(error.localizedDescription)"
                    }
                case .success(let transcript):
                    print("📝 STT transcript length: \(transcript.count) chars")
                    self.handleTranscript(transcript)
                }
            }
        }
    }

    private func handleTranscript(_ transcript: String) {
        DispatchQueue.main.async {
            self.transcriptText = transcript
            self.processingStage = .summarizing
        }
        summarizeWithClaude(transcript: transcript) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isUploading = false
                    self.processingStage = .idle
                    self.errorMessage = "요약 실패: \(error.localizedDescription)"
                }
            case .success(let summary):
                DispatchQueue.main.async {
                    self.summaryText = summary
                    self.processingStage = .uploading
                }
                self.createNotionPage(summary: summary, transcript: transcript) { notionResult in
                    DispatchQueue.main.async {
                        self.isUploading = false
                        switch notionResult {
                        case .success(let pageURL):
                            self.processingStage = .completed
                            self.notionPageURL = pageURL
                            let title = self.buildNotionTitle(from: summary)
                            self.sendSlackNotification(title: title, notionURL: pageURL)
                            self.pushSummaryToGitHub(summary: summary, title: title)
                        case .failure(let error):
                            self.processingStage = .idle
                            self.errorMessage = "Notion 등록 실패: \(error.localizedDescription)"
                        }
                    }
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
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 900
        config.timeoutIntervalForResource = 900
        let session = URLSession(configuration: config)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let openAIKey = SettingsManager.shared.openAIKey
        request.setValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 900
        
        var body = Data()
        
        // model
        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append("whisper-1\(lineBreak)".data(using: .utf8)!)
        
        // language
        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append("ko\(lineBreak)".data(using: .utf8)!)
        
        // file
        body.append("--\(boundary)\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\(lineBreak)".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\(lineBreak)\(lineBreak)".data(using: .utf8)!)
        body.append(audioData)
        body.append(lineBreak.data(using: .utf8)!)
        
        // end
        body.append("--\(boundary)--\(lineBreak)".data(using: .utf8)!)
        
        let task = session.uploadTask(with: request, from: body) { [weak self] data, response, error in
            if let error = error {
                // 취소된 경우 에러 무시
                if (error as NSError).code == NSURLErrorCancelled { return }
                completion(.failure(error))
                return
            }
            guard self?.isCancelled != true else { return }
            
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

        currentTask = task
        task.resume()
    }

    // MARK: - Anthropic Claude 요약
    private struct AnthropicMessageResponse: Decodable {
        struct ContentBlock: Decodable {
            let type: String
            let text: String?
        }

        let content: [ContentBlock]
    }

    private func summarizeWithClaude(transcript: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            completion(.failure(NSError(domain: "AudioRecorder", code: -30, userInfo: [NSLocalizedDescriptionKey: "잘못된 Claude API URL"])))
            return
        }

        let anthropicKey = SettingsManager.shared.anthropicKey
        let model = "claude-sonnet-4-20250514"

        // 위키 컨텍스트 로드 → 성공 시 위키 기반 프롬프트, 실패 시 기존 하드코딩 프롬프트
        let wikiPath = SettingsManager.shared.wikiPath
        let wikiContext = WikiContextLoader.shared.loadContext(from: wikiPath)
        let systemPrompt = WikiContextLoader.shared.buildSystemPrompt(wikiContext: wikiContext)

        let userPrompt = """
아래 STT 자동 변환 텍스트를 정제된 회의록으로 재구성해주세요.

## 1단계: STT 원문 보정 (요약 전 반드시 수행)
시스템 프롬프트의 **STT 음성인식 보정 사전**을 참조하여 다음을 보정하세요:
1. **도메인 용어 보정**: 오인식된 회사명·서비스명·기술 용어를 정확한 표기로 교정
2. **팀원 이름 보정**: 이름/호칭을 @성+이름 형태로 통일
3. **문맥 기반 보정**: 보정 사전에 없더라도 부동산·IT 도메인 문맥상 명백히 잘못된 표현은 교정
4. **구어체 정제**: 말버릇("어...", "그니까"), 중복 발언, 문장 깨짐을 자연스럽게 다듬기

## 2단계: 보정된 텍스트를 아래 형식으로 요약

## 출력 규칙

### 멤버 멘션
- 팀원 이름은 반드시 **@성+이름** 형태 (예: "상용님" → "@박상용", "영기" → "@최영기")

### 아래 마크다운 구조를 반드시 유지

# 회의 제목
- 회의 목적 한 줄 요약 (예: "RTB 개편 매물 관리 API 스펙 정리 회의")

---

## 📝 주요 논의 내용
- 기능/이슈/요구사항 단위로 구조화
- 도메인 엔티티(Building, Product, Deal 등)가 언급되면 명시
- 필요 시 bullet 하위 depth 사용

---

## 📌 결정된 사항(Decision)
- 최종 합의 내용만 명확히 정리
- 없으면 "해당 없음"

---

## ❗ 해결해야 할 이슈
- 미해결 문제, 리스크, 기술 부채
- 담당자 @이름 포함

---

## 📅 Action Items (할 일)
- [ ] @담당자 – 할 일 (기한이 언급되면 추가)

---

## 🗂 참고 메모
- 필요한 경우만 정리
- 잡담/중복 발언은 제거

---

[회의 원문 시작]
\(transcript)
[회의 원문 끝]
"""

        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 4000,
            "temperature": 0.2,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": userPrompt]
                    ]
                ]
            ]
        ]

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 900
        config.timeoutIntervalForResource = 900
        let session = URLSession(configuration: config)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(anthropicKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 900

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            completion(.failure(error))
            return
        }

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                if (error as NSError).code == NSURLErrorCancelled { return }
                completion(.failure(error))
                return
            }
            guard self?.isCancelled != true else { return }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "AudioRecorder", code: -31, userInfo: [NSLocalizedDescriptionKey: "잘못된 Claude 응답 형식"])))
                return
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                completion(.failure(NSError(domain: "AudioRecorder", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Claude 응답 코드: \(httpResponse.statusCode)"])))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: "AudioRecorder", code: -32, userInfo: [NSLocalizedDescriptionKey: "Claude 응답 데이터 없음"])))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(AnthropicMessageResponse.self, from: data)
                let text = decoded.content.compactMap { $0.text }.joined()
                completion(.success(text))
            } catch {
                completion(.failure(error))
            }
        }

        currentTask = task
        task.resume()
    }

    // MARK: - Notion 페이지 생성
    private struct NotionPageResponse: Decodable {
        let url: String
    }

    private func createNotionPage(summary: String, transcript: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "https://api.notion.com/v1/pages") else {
            completion(.failure(NSError(domain: "AudioRecorder", code: -40, userInfo: [NSLocalizedDescriptionKey: "잘못된 Notion API URL"])))
            return
        }

        let notionKey = SettingsManager.shared.notionKey
        let databaseId = "173321af000280d787eae2ffeb63c974"

        let title = buildNotionTitle(from: summary)
        let children = buildNotionChildren(summary: summary, transcript: transcript)

        let payload: [String: Any] = [
            "parent": ["database_id": databaseId],
            "properties": [
                "이름": [
                    "title": [
                        ["type": "text", "text": ["content": title]]
                    ]
                ],
                "키워드": [
                    "multi_select": [
                        ["name": "회의록[개발협의]"]
                    ]
                ],
                "상태": [
                    "status": ["name": "완료"]
                ]
            ],
            "children": children
        ]

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 900
        config.timeoutIntervalForResource = 900
        let session = URLSession(configuration: config)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(notionKey)", forHTTPHeaderField: "Authorization")
        request.setValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
        request.timeoutInterval = 900

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            completion(.failure(error))
            return
        }

        let task = session.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                if (error as NSError).code == NSURLErrorCancelled { return }
                completion(.failure(error))
                return
            }
            guard self?.isCancelled != true else { return }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(NSError(domain: "AudioRecorder", code: -41, userInfo: [NSLocalizedDescriptionKey: "잘못된 Notion 응답 형식"])))
                return
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                completion(.failure(NSError(domain: "AudioRecorder", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Notion 응답 코드: \(httpResponse.statusCode)"])))
                return
            }

            guard let data = data else {
                completion(.failure(NSError(domain: "AudioRecorder", code: -42, userInfo: [NSLocalizedDescriptionKey: "Notion 응답 데이터 없음"])))
                return
            }

            do {
                let decoded = try JSONDecoder().decode(NotionPageResponse.self, from: data)
                completion(.success(decoded.url))
            } catch {
                completion(.failure(error))
            }
        }

        currentTask = task
        task.resume()
    }

    private func buildNotionTitle(from summary: String) -> String {
        let lines = summary.split(separator: "\n", omittingEmptySubsequences: true)
        let rawTitle = lines.first(where: { $0.hasPrefix("# ") })?.replacingOccurrences(of: "# ", with: "")
            ?? "회의록"

        let now = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyMMdd"
        let datePrefix = formatter.string(from: now)

        return "\(datePrefix) \(rawTitle)"
    }

    private func buildNotionChildren(summary: String, transcript: String) -> [[String: Any]] {
        var children: [[String: Any]] = []

        // 요약: 마크다운을 Notion 블록으로 변환
        children.append(contentsOf: parseMarkdownToNotionBlocks(summary))

        // 원문: 기존 plain text 방식 유지
        children.append(notionDividerBlock())
        children.append(contentsOf: notionHeading2Blocks("[원문]"))
        chunkText(transcript, maxLength: 2000).forEach { chunk in
            children.append(contentsOf: notionParagraphBlocks(chunk))
        }

        return children
    }

    private let notionRichTextLimit = 2000
    private let notionRichTextArrayLimit = 100

    private func notionHeading2Blocks(_ text: String) -> [[String: Any]] {
        return buildRichTextBlocks(type: "heading_2", richText: parseRichText(text))
    }

    private func notionParagraphBlocks(_ text: String) -> [[String: Any]] {
        return buildRichTextBlocks(type: "paragraph", richText: parseRichText(text))
    }

    private func chunkText(_ text: String, maxLength: Int) -> [String] {
        var chunks: [String] = []
        var start = text.startIndex

        while start < text.endIndex {
            let endIndex = text.index(start, offsetBy: maxLength, limitedBy: text.endIndex) ?? text.endIndex
            let slice = String(text[start..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !slice.isEmpty {
                chunks.append(slice)
            }
            start = endIndex
        }

        return chunks
    }

    private func splitTextByLength(_ text: String, maxLength: Int) -> [String] {
        guard maxLength > 0 else { return [text] }

        var chunks: [String] = []
        var start = text.startIndex

        while start < text.endIndex {
            let endIndex = text.index(start, offsetBy: maxLength, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(String(text[start..<endIndex]))
            start = endIndex
        }

        return chunks
    }

    private func chunkRichTextArray(_ richText: [[String: Any]], maxCount: Int) -> [[[String: Any]]] {
        guard maxCount > 0 else { return [richText] }
        guard !richText.isEmpty else { return [] }

        var chunks: [[[String: Any]]] = []
        var index = 0

        while index < richText.count {
            let end = min(index + maxCount, richText.count)
            chunks.append(Array(richText[index..<end]))
            index = end
        }

        return chunks
    }

    private func buildRichTextBlocks(type: String, richText: [[String: Any]], extra: [String: Any] = [:], children: [[String: Any]]? = nil) -> [[String: Any]] {
        let chunks = chunkRichTextArray(richText, maxCount: notionRichTextArrayLimit)
        return chunks.enumerated().map { index, chunk in
            var content: [String: Any] = ["rich_text": chunk]
            extra.forEach { key, value in
                content[key] = value
            }

            if let children = children, !children.isEmpty, index == 0 {
                content["children"] = children
            }

            return [
                "object": "block",
                "type": type,
                type: content
            ]
        }
    }
    
    // MARK: - 마크다운 → Notion 블록 변환

    /// 인라인 마크다운을 Notion rich_text 배열로 변환
    private func parseRichText(_ text: String) -> [[String: Any]] {
        let pattern = "(`[^`]+`|\\*\\*[^*]+\\*\\*|~~[^~]+~~|\\*[^*]+\\*)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [richTextSegment(text)]
        }

        let nsText = text as NSString
        var result: [[String: Any]] = []
        var lastEnd = 0
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            let matchRange = match.range

            if matchRange.location > lastEnd {
                let plain = nsText.substring(with: NSRange(location: lastEnd, length: matchRange.location - lastEnd))
                if !plain.isEmpty {
                    appendRichText(plain, to: &result)
                }
            }

            let matched = nsText.substring(with: matchRange)
            if matched.hasPrefix("**") && matched.hasSuffix("**") {
                let content = String(matched.dropFirst(2).dropLast(2))
                appendRichText(content, bold: true, to: &result)
            } else if matched.hasPrefix("~~") && matched.hasSuffix("~~") {
                let content = String(matched.dropFirst(2).dropLast(2))
                appendRichText(content, strikethrough: true, to: &result)
            } else if matched.hasPrefix("`") && matched.hasSuffix("`") {
                let content = String(matched.dropFirst(1).dropLast(1))
                appendRichText(content, code: true, to: &result)
            } else if matched.hasPrefix("*") && matched.hasSuffix("*") {
                let content = String(matched.dropFirst(1).dropLast(1))
                appendRichText(content, italic: true, to: &result)
            }

            lastEnd = matchRange.location + matchRange.length
        }

        if lastEnd < nsText.length {
            let remaining = nsText.substring(from: lastEnd)
            if !remaining.isEmpty {
                appendRichText(remaining, to: &result)
            }
        }

        if result.isEmpty {
            appendRichText(text, to: &result)
        }

        return result
    }

    private func appendRichText(_ text: String, bold: Bool = false, italic: Bool = false, code: Bool = false, strikethrough: Bool = false, to result: inout [[String: Any]]) {
        splitTextByLength(text, maxLength: notionRichTextLimit).forEach { piece in
            guard !piece.isEmpty else { return }
            result.append(richTextSegment(piece, bold: bold, italic: italic, code: code, strikethrough: strikethrough))
        }
    }

    private func richTextSegment(_ text: String, bold: Bool = false, italic: Bool = false, code: Bool = false, strikethrough: Bool = false) -> [String: Any] {
        var segment: [String: Any] = [
            "type": "text",
            "text": ["content": text]
        ]
        if bold || italic || code || strikethrough {
            var annotations: [String: Any] = [:]
            if bold { annotations["bold"] = true }
            if italic { annotations["italic"] = true }
            if code { annotations["code"] = true }
            if strikethrough { annotations["strikethrough"] = true }
            segment["annotations"] = annotations
        }
        return segment
    }

    /// 마크다운 텍스트를 줄 단위로 파싱하여 Notion 블록 배열로 변환
    private func parseMarkdownToNotionBlocks(_ markdown: String) -> [[String: Any]] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [[String: Any]] = []

        var i = 0
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            if trimmed.hasPrefix("### ") {
                let content = String(trimmed.dropFirst(4))
                blocks.append(contentsOf: notionHeading3Blocks(content))
            } else if trimmed.hasPrefix("## ") {
                let content = String(trimmed.dropFirst(3))
                blocks.append(contentsOf: notionHeading2Blocks(content))
            } else if trimmed.hasPrefix("# ") {
                let content = String(trimmed.dropFirst(2))
                blocks.append(contentsOf: notionHeading1Blocks(content))
            } else if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(notionDividerBlock())
            } else if trimmed.hasPrefix("- [ ] ") {
                let content = String(trimmed.dropFirst(6))
                blocks.append(contentsOf: notionTodoBlocks(content, checked: false))
            } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                let content = String(trimmed.dropFirst(6))
                blocks.append(contentsOf: notionTodoBlocks(content, checked: true))
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") {
                let content = String(trimmed.dropFirst(2))

                // 들여쓴 하위 bullet 수집
                var children: [[String: Any]] = []
                while i + 1 < lines.count {
                    let nextLine = lines[i + 1]
                    let nextTrimmed = nextLine.trimmingCharacters(in: .whitespaces)
                    let isIndented = nextLine.hasPrefix(" ") || nextLine.hasPrefix("\t")

                    if isIndented && (nextTrimmed.hasPrefix("- ") || nextTrimmed.hasPrefix("• ")) {
                        let childContent = String(nextTrimmed.dropFirst(2))
                        children.append(contentsOf: notionBulletBlocks(childContent))
                        i += 1
                    } else {
                        break
                    }
                }

                if children.isEmpty {
                    blocks.append(contentsOf: notionBulletBlocks(content))
                } else {
                    blocks.append(contentsOf: notionBulletBlocksWithChildren(content, children: children))
                }
            } else {
                blocks.append(contentsOf: notionParagraphBlocks(trimmed))
            }

            i += 1
        }

        return blocks
    }

    private func notionHeading1Blocks(_ text: String) -> [[String: Any]] {
        return buildRichTextBlocks(type: "heading_1", richText: parseRichText(text))
    }

    private func notionHeading3Blocks(_ text: String) -> [[String: Any]] {
        return buildRichTextBlocks(type: "heading_3", richText: parseRichText(text))
    }

    private func notionDividerBlock() -> [String: Any] {
        return [
            "object": "block",
            "type": "divider",
            "divider": [:] as [String: Any]
        ]
    }

    private func notionTodoBlocks(_ text: String, checked: Bool) -> [[String: Any]] {
        return buildRichTextBlocks(type: "to_do", richText: parseRichText(text), extra: ["checked": checked])
    }

    private func notionBulletBlocks(_ text: String) -> [[String: Any]] {
        return buildRichTextBlocks(type: "bulleted_list_item", richText: parseRichText(text))
    }

    private func notionBulletBlocksWithChildren(_ text: String, children: [[String: Any]]) -> [[String: Any]] {
        return buildRichTextBlocks(type: "bulleted_list_item", richText: parseRichText(text), children: children)
    }

    // MARK: - Slack 웹훅 알림

    private func sendSlackNotification(title: String, notionURL: String) {
        guard let url = URL(string: "REDACTED_SLACK_WEBHOOK") else { return }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let timeString = formatter.string(from: Date())

        let message = "📝 *\(title)*\n🕐 \(timeString)\n🔗 <\(notionURL)|Notion에서 보기>"

        let payload: [String: Any] = ["text": message]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            print("⚠️ Slack 웹훅 페이로드 생성 실패: \(error)")
            return
        }

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                print("⚠️ Slack 웹훅 전송 실패: \(error.localizedDescription)")
                return
            }
            if let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) {
                print("✅ Slack 웹훅 전송 성공")
            }
        }.resume()
    }

    // MARK: - GitHub 위키 레포에 회의록 푸시

    private let wikiRepoOwner = "dev-rsquare"
    private let wikiRepoName = "rtb-wiki"
    private let wikiMeetingsPath = "rtb-unified/meetings"

    private func pushSummaryToGitHub(summary: String, title: String) {
        let githubToken = SettingsManager.shared.githubToken
        guard !githubToken.isEmpty else {
            print("⚠️ GitHub 토큰이 설정되지 않아 위키 푸시를 건너뜁니다.")
            return
        }

        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ko_KR")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: now)

        // 제목에서 파일명 생성: 공백 → 하이픈, 특수문자 제거
        let rawTitle = extractRawTitle(from: summary)
        let sanitizedTitle = rawTitle
            .replacingOccurrences(of: " ", with: "-")
            .components(separatedBy: CharacterSet.alphanumerics
                .union(.init(charactersIn: "-_가-힣ㄱ-ㅎㅏ-ㅣ"))
                .inverted)
            .joined()

        let fileName = "\(dateString)-\(sanitizedTitle).md"
        let filePath = "\(wikiMeetingsPath)/\(fileName)"
        let commitMessage = "feat: \(dateString) \(rawTitle) 회의록"

        print("📤 GitHub 위키 푸시: \(filePath)")

        // GitHub Contents API: PUT /repos/{owner}/{repo}/contents/{path}
        guard let url = URL(string: "https://api.github.com/repos/\(wikiRepoOwner)/\(wikiRepoName)/contents/\(filePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filePath)") else {
            print("⚠️ GitHub API URL 생성 실패")
            return
        }

        let contentBase64 = Data(summary.utf8).base64EncodedString()

        let payload: [String: Any] = [
            "message": commitMessage,
            "content": contentBase64,
            "branch": "main"
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(githubToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            print("⚠️ GitHub 페이로드 생성 실패: \(error)")
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("⚠️ GitHub 위키 푸시 실패: \(error.localizedDescription)")
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                print("⚠️ GitHub 응답 형식 오류")
                return
            }

            if (200..<300).contains(httpResponse.statusCode) {
                print("✅ GitHub 위키 푸시 성공: \(filePath)")
            } else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "응답 없음"
                print("⚠️ GitHub 위키 푸시 실패 (HTTP \(httpResponse.statusCode)): \(body)")
            }
        }.resume()
    }

    /// 요약 마크다운에서 순수 제목 텍스트만 추출
    private func extractRawTitle(from summary: String) -> String {
        let lines = summary.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.first(where: { $0.hasPrefix("# ") })?
            .replacingOccurrences(of: "# ", with: "")
            ?? "회의록"
    }

    private let maxRetryCount = 2

    /// 대용량 오디오 파일을 청크로 나누어 병렬 STT 수행 후 하나의 텍스트로 합칩니다.
    /// 각 청크는 실패 시 최대 maxRetryCount회 재시도하며, 재시도 후에도 실패하면 전체 실패 처리합니다.
    private func transcribeLargeAudio(fileURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        let asset = AVURLAsset(url: fileURL)
        let durationSeconds = CMTimeGetSeconds(asset.duration)

        guard durationSeconds.isFinite && durationSeconds > 0 else {
            completion(.failure(NSError(domain: "AudioRecorder",
                                        code: -20,
                                        userInfo: [NSLocalizedDescriptionKey: "오디오 duration 정보를 가져오지 못했습니다."])))
            return
        }

        let chunkDuration: Double = 600.0
        let chunkCount = max(1, Int(ceil(durationSeconds / chunkDuration)))

        print("🔪 Splitting audio into \(chunkCount) chunks (duration: \(durationSeconds) seconds), parallel processing")

        // 1) 모든 청크를 먼저 내보내기
        let exportGroup = DispatchGroup()
        var chunkURLs: [Int: URL] = [:]
        var exportError: Error?
        let lock = NSLock()

        for i in 0..<chunkCount {
            exportGroup.enter()
            let startTime = Double(i) * chunkDuration
            let remaining = durationSeconds - startTime
            let thisDuration = min(chunkDuration, remaining)

            print("🔪 Exporting chunk \(i + 1)/\(chunkCount) [start=\(startTime), duration=\(thisDuration)]")

            exportAudioChunk(asset: asset, startTime: startTime, duration: thisDuration) { result in
                lock.lock()
                switch result {
                case .success(let url):
                    chunkURLs[i] = url
                case .failure(let error):
                    if exportError == nil { exportError = error }
                }
                lock.unlock()
                exportGroup.leave()
            }
        }

        exportGroup.notify(queue: .global(qos: .userInitiated)) { [weak self] in
            guard let self = self else { return }
            guard self.isCancelled != true else { return }

            if let error = exportError {
                // 내보내기 실패한 청크 임시 파일 정리
                lock.lock()
                let urls = Array(chunkURLs.values)
                lock.unlock()
                urls.forEach { try? FileManager.default.removeItem(at: $0) }
                completion(.failure(error))
                return
            }

            // 2) 병렬 STT 처리 (재시도 포함)
            self.transcribeChunksInParallel(
                chunkURLs: chunkURLs,
                chunkCount: chunkCount,
                originalFileName: fileURL.lastPathComponent,
                completion: completion
            )
        }
    }

    /// 내보내기 완료된 청크들을 병렬로 STT 처리합니다. 실패 시 재시도합니다.
    private func transcribeChunksInParallel(
        chunkURLs: [Int: URL],
        chunkCount: Int,
        originalFileName: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let sttGroup = DispatchGroup()
        var transcripts: [Int: String] = [:]
        var failedChunks: [Int: Error] = [:]
        let lock = NSLock()

        for i in 0..<chunkCount {
            guard let chunkURL = chunkURLs[i] else { continue }
            sttGroup.enter()

            transcribeChunkWithRetry(chunkURL: chunkURL, index: i, originalFileName: originalFileName, retryCount: 0) { result in
                lock.lock()
                switch result {
                case .success(let text):
                    transcripts[i] = text
                case .failure(let error):
                    failedChunks[i] = error
                }
                lock.unlock()
                sttGroup.leave()
            }
        }

        sttGroup.notify(queue: .global(qos: .userInitiated)) {
            // 임시 파일 정리
            for url in chunkURLs.values {
                try? FileManager.default.removeItem(at: url)
            }

            lock.lock()
            let failed = failedChunks
            let results = transcripts
            lock.unlock()

            if !failed.isEmpty {
                let failedIndices = failed.keys.sorted().map { "\($0 + 1)" }.joined(separator: ", ")
                let firstError = failed.values.first!
                completion(.failure(NSError(
                    domain: "AudioRecorder",
                    code: -23,
                    userInfo: [NSLocalizedDescriptionKey: "STT 실패 (청크 \(failedIndices)): \(firstError.localizedDescription)"]
                )))
                return
            }

            let merged = (0..<chunkCount).compactMap { results[$0] }.joined(separator: " ")
            print("📝 STT 병렬 처리 완료 (총 \(chunkCount)개 청크, \(merged.count)자)")
            completion(.success(merged))
        }
    }

    /// 단일 청크 STT를 수행하고, 실패 시 maxRetryCount회까지 재시도합니다.
    private func transcribeChunkWithRetry(
        chunkURL: URL,
        index: Int,
        originalFileName: String,
        retryCount: Int,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard isCancelled != true else { return }

        let chunkData: Data
        do {
            chunkData = try Data(contentsOf: chunkURL)
        } catch {
            completion(.failure(error))
            return
        }

        let chunkFileName = "chunk-\(index)-\(originalFileName)"
        print("🎙 STT 청크 \(index + 1) 처리 중 (시도 \(retryCount + 1)/\(maxRetryCount + 1))")

        transcribeWithOpenAI(audioData: chunkData, fileName: chunkFileName) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let text):
                print("✅ STT 청크 \(index + 1) 완료 (\(text.count)자)")
                completion(.success(text))
            case .failure(let error):
                if retryCount < self.maxRetryCount {
                    let delay = Double(retryCount + 1) * 2.0
                    print("⚠️ STT 청크 \(index + 1) 실패, \(delay)초 후 재시도 (\(retryCount + 1)/\(self.maxRetryCount))")
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
                        self.transcribeChunkWithRetry(
                            chunkURL: chunkURL,
                            index: index,
                            originalFileName: originalFileName,
                            retryCount: retryCount + 1,
                            completion: completion
                        )
                    }
                } else {
                    print("❌ STT 청크 \(index + 1) 최종 실패: \(error.localizedDescription)")
                    completion(.failure(error))
                }
            }
        }
    }

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
