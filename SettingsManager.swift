import Foundation
import Combine
import SwiftUI

final class SettingsManager: ObservableObject {
    var objectWillChange: ObservableObjectPublisher
    
    static let shared = SettingsManager()
    private let openAIKeyKey = "OPEN_AI_KEY"
    private let anthropicKeyKey = "ANTHROPIC_KEY"
    private let notionKeyKey = "NOTION_API_KEY"
    private let wikiPathKey = "WIKI_PATH"
    private let wikiBookmarkKey = "WIKI_BOOKMARK"

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

        openAIKey = savedOpenAI?.isEmpty == false ? savedOpenAI! : envOpenAI
        anthropicKey = savedAnthropic?.isEmpty == false ? savedAnthropic! : envAnthropic
        notionKey = savedNotion?.isEmpty == false ? savedNotion! : envNotion
        wikiPath = savedWikiPath ?? ""
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
