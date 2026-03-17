import Foundation
import Combine
import SwiftUI

// MARK: - 화자 분리 모드

enum DiarizationMode: Int, CaseIterable {
    case off = 0        // 화자 분리 미사용
    case claude = 1     // Claude 추론 (추가 설치 불필요)
    case pyannote = 2   // pyannote.audio (Python + HuggingFace 토큰 필요)

    var label: String {
        switch self {
        case .off: return "OFF"
        case .claude: return "Claude 추론"
        case .pyannote: return "pyannote (고급)"
        }
    }

    var description: String {
        switch self {
        case .off: return "화자 분리 없이 STT 텍스트를 그대로 요약합니다."
        case .claude: return "Whisper 타임스탬프 + Claude 문맥 분석으로 화자를 구분합니다. 추가 설치 불필요."
        case .pyannote: return "pyannote.audio 음성 특성 분석으로 정확하게 화자를 구분합니다. Python + torch 설치 필요."
        }
    }
}

final class SettingsManager: ObservableObject {
    var objectWillChange: ObservableObjectPublisher

    static let shared = SettingsManager()
    private let openAIKeyKey = "OPEN_AI_KEY"
    private let anthropicKeyKey = "ANTHROPIC_KEY"
    private let notionKeyKey = "NOTION_API_KEY"
    private let wikiPathKey = "WIKI_PATH"
    private let wikiBookmarkKey = "WIKI_BOOKMARK"
    private let githubTokenKey = "GITHUB_TOKEN"
    private let diarizationModeKey = "DIARIZATION_MODE"
    private let huggingFaceTokenKey = "HUGGINGFACE_TOKEN"
    private let pythonPathKey = "PYTHON_PATH"
    private let wikiRagURLKey = "WIKI_RAG_URL"
    private let notionDatabaseIdKey = "NOTION_DATABASE_ID"

    @Published var openAIKey: String = "" {
        didSet {
            UserDefaults.standard.set(openAIKey, forKey: openAIKeyKey)
        }
    }
    @Published var anthropicKey: String = "" {
        didSet {
            UserDefaults.standard.set(anthropicKey, forKey: anthropicKeyKey)
        }
    }
    @Published var notionKey: String = "" {
        didSet {
            UserDefaults.standard.set(notionKey, forKey: notionKeyKey)
        }
    }
    @Published var wikiPath: String = "" {
        didSet {
            UserDefaults.standard.set(wikiPath, forKey: wikiPathKey)
        }
    }
    @Published var githubToken: String = "" {
        didSet {
            UserDefaults.standard.set(githubToken, forKey: githubTokenKey)
        }
    }
    @Published var diarizationMode: DiarizationMode = .off {
        didSet {
            UserDefaults.standard.set(diarizationMode.rawValue, forKey: diarizationModeKey)
        }
    }
    @Published var huggingFaceToken: String = "" {
        didSet {
            UserDefaults.standard.set(huggingFaceToken, forKey: huggingFaceTokenKey)
        }
    }
    @Published var pythonPath: String = "/opt/homebrew/bin/python3" {
        didSet {
            UserDefaults.standard.set(pythonPath, forKey: pythonPathKey)
        }
    }
    @Published var wikiRagURL: String = "http://localhost:8686" {
        didSet {
            UserDefaults.standard.set(wikiRagURL, forKey: wikiRagURLKey)
        }
    }
    @Published var notionDatabaseId: String = "173321af000280d787eae2ffeb63c974" {
        didSet {
            UserDefaults.standard.set(notionDatabaseId, forKey: notionDatabaseIdKey)
        }
    }

    private init() {
        objectWillChange = ObservableObjectPublisher()
        
        // 1) UserDefaults에 저장된 값이 있으면 우선 사용
        let savedOpenAI = UserDefaults.standard.string(forKey: openAIKeyKey)
        let savedAnthropic = UserDefaults.standard.string(forKey: anthropicKeyKey)
        let savedNotion = UserDefaults.standard.string(forKey: notionKeyKey)

        // 2) 없으면 환경변수에서 기본값 로드
        let env = ProcessInfo.processInfo.environment
        let envOpenAI = env["OPENAI_API_KEY"] ?? ""
        let envAnthropic = env["ANTHROPIC_KEY"] ?? ""
        let envNotion = env["NOTION_API_KEY"] ?? ""

        let savedWikiPath = UserDefaults.standard.string(forKey: wikiPathKey)
        let savedGithubToken = UserDefaults.standard.string(forKey: githubTokenKey)
        let envGithubToken = env["GITHUB_TOKEN"] ?? ""
        let savedHFToken = UserDefaults.standard.string(forKey: huggingFaceTokenKey)
        let savedPythonPath = UserDefaults.standard.string(forKey: pythonPathKey)

        openAIKey = savedOpenAI?.isEmpty == false ? savedOpenAI! : envOpenAI
        anthropicKey = savedAnthropic?.isEmpty == false ? savedAnthropic! : envAnthropic
        notionKey = savedNotion?.isEmpty == false ? savedNotion! : envNotion
        wikiPath = savedWikiPath ?? ""
        githubToken = savedGithubToken?.isEmpty == false ? savedGithubToken! : envGithubToken
        diarizationMode = DiarizationMode(rawValue: UserDefaults.standard.integer(forKey: diarizationModeKey)) ?? .off
        huggingFaceToken = savedHFToken ?? ""
        pythonPath = savedPythonPath?.isEmpty == false ? savedPythonPath! : "/opt/homebrew/bin/python3"

        let savedWikiRagURL = UserDefaults.standard.string(forKey: wikiRagURLKey)
        wikiRagURL = savedWikiRagURL?.isEmpty == false ? savedWikiRagURL! : "http://localhost:8686"
        let savedNotionDbId = UserDefaults.standard.string(forKey: notionDatabaseIdKey)
        notionDatabaseId = savedNotionDbId?.isEmpty == false ? savedNotionDbId! : "173321af000280d787eae2ffeb63c974"
    }
    
    func masked(_ text: String) -> String {
        guard text.count > 4 else { return String(repeating: "*", count: max(0, text.count)) }
        let maskedCount = text.count - 4
        let mask = String(repeating: "*", count: maskedCount)
        let suffix = text.suffix(4)
        return mask + suffix
    }
    
    // MARK: - 위키 경로 북마크 (샌드박스 환경에서 재시작 후에도 접근 가능)

    func saveWikiBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmarkData, forKey: wikiBookmarkKey)
            wikiPath = url.path
        } catch {
            print("⚠️ 위키 북마크 저장 실패: \(error.localizedDescription)")
        }
    }

    func resolveWikiBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: wikiBookmarkKey) else {
            return nil
        }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                saveWikiBookmark(for: url)
            }
            return url
        } catch {
            print("⚠️ 위키 북마크 복원 실패: \(error.localizedDescription)")
            return nil
        }
    }

    // 외부에서 환경변수 갱신
    func save(openAI: String, anthropic: String, notion: String) {
        openAIKey = openAI
        anthropicKey = anthropic
        notionKey = notion
    }
}
