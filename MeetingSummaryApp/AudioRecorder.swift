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
    case transcribing = 1    // STT 변환 중
    case summarizing = 2     // 요약 중
    case uploading = 3       // Notion 등록 중
    case completed = 4       // 완료

    var description: String {
        switch self {
        case .idle: return ""
        case .transcribing: return "음성을 텍스트로 변환 중..."
        case .summarizing: return "회의 내용 요약 중..."
        case .uploading: return "Notion에 등록 중..."
        case .completed: return "완료"
        }
    }

    var progress: Double {
        switch self {
        case .idle: return 0.0
        case .transcribing: return 0.33
        case .summarizing: return 0.66
        case .uploading: return 0.9
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
        // 1) 먼저 마이크 권한 체크
        checkMicPermission { [weak self] granted in
            guard let self = self, granted else { return }

            // 2) 권한이 허용된 경우에만 실제 녹음 시작 로직 수행
            // 업로드/재생 관련 상태 초기화
            self.transcriptText = nil
            self.summaryText = nil
            self.notionPageURL = nil
            self.errorMessage = nil
            self.processingStage = .idle
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

        uploadAudio(fileURL: url)
    }
    
    // MARK: - 업로드

    private func uploadAudio(fileURL: URL) {
        isUploading = true
        isCancelled = false
        processingStage = .transcribing
        errorMessage = nil
        transcriptText = nil
        summaryText = nil
        notionPageURL = nil
        
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

        let systemPrompt = """
당신은 알스퀘어(RSquare) RTB 개발팀의 회의록 전문 정리자입니다.

## 회사·서비스 배경
- 알스퀘어: 국내 대표 상업용 부동산 종합 서비스 기업
- RTB(RSquare To-Be): 상업용 부동산 중개 플랫폼. 오피스·리테일·물류/산업 부동산의 매물 관리, 거래 추적, 고객 관리를 담당
- 레거시 RTB 전면 개편 프로젝트 진행 중 (2026년 말 출시 예정 Nest, Nuxt 기반)
- 백엔드: Kotlin/Spring Boot, PostgreSQL, AWS(EKS)
- 프론트엔드: React/TypeScript
- 환경: INT(개발), STG(스테이징), PRD(운영)

## 도메인 핵심 용어
STT에서 아래 용어가 다르게 인식될 수 있으니 문맥에 맞게 보정하세요:
- Building(건물) → Unit(호실) → Product(매물) → Deal(딜/거래): 핵심 엔티티 계층 구조
- Client(거래처): 임대인/매도인 (매물 제공자)
- Customer(고객): 임차인/매수인 (매물 수요자)
- PNU: 필지고유번호
- 알스퀘어온(rsquareon): 서비스 도메인
- 딜 플로우: 상담 → 투어 → 협상 → 계약
- 테이블 prefix: obj_(객체), prd_(상품), mbr_(멤버), gtd_(거래), cmm_(공통), sys_(시스템)
- QueryPie: 운영 DB 접근 도구

## 팀원 (이름 언급 시 반드시 @성+이름으로 표기)
- 개발자: @박상용(팀장), @복영균(이사), @양준철(TL), @이종호, @홍채민, @최영기, @조재용, @김민정
- PM(기획): @이미정, @최병선, @서연정
"""

        let userPrompt = """
아래 STT 자동 변환 텍스트를 정제된 회의록으로 재구성해주세요.
구어체·중복·말버릇·문장 깨짐을 자연스럽게 다듬고, 도메인 용어는 올바른 표기로 보정하세요.

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
            "max_tokens": 2500,
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
        
        let chunkDuration: Double = 600.0
        let chunkCount = max(1, Int(ceil(durationSeconds / chunkDuration)))
        
        print("🔪 Splitting audio into \(chunkCount) chunks (duration: \(durationSeconds) seconds)")
        
        var transcripts: [String] = Array(repeating: "", count: chunkCount)
        var currentIndex = 0
        
        func processNextChunk() {
            if currentIndex >= chunkCount {
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
