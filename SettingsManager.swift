import Foundation
import Combine
import SwiftUI

final class SettingsManager: ObservableObject {
    var objectWillChange: ObservableObjectPublisher
    
    static let shared = SettingsManager()
    private let openAIKeyKey = "OPEN_AI_KEY"
    private let anthropicKeyKey = "ANTHROPIC_KEY"
    
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
    
    private init() {
        objectWillChange = ObservableObjectPublisher()
        
        // 1) UserDefaults에 저장된 값이 있으면 우선 사용
        let savedOpenAI = UserDefaults.standard.string(forKey: openAIKeyKey)
        let savedAnthropic = UserDefaults.standard.string(forKey: anthropicKeyKey)
        
        // 2) 없으면 환경변수에서 기본값 로드
        let env = ProcessInfo.processInfo.environment
        let envOpenAI = env["OPEN_AI_KEY"] ?? ""
        let envAnthropic = env["ANTHROPIC_KEY"] ?? ""
        
        openAIKey = savedOpenAI?.isEmpty == false ? savedOpenAI! : envOpenAI
        anthropicKey = savedAnthropic?.isEmpty == false ? savedAnthropic! : envAnthropic
    }
    
    func masked(_ text: String) -> String {
        guard text.count > 4 else { return String(repeating: "*", count: max(0, text.count)) }
        let maskedCount = text.count - 4
        let mask = String(repeating: "*", count: maskedCount)
        let suffix = text.suffix(4)
        return mask + suffix
    }
    
    // 외부에서 환경변수 갱신
    func save(openAI: String, anthropic: String) {
        openAIKey = openAI
        anthropicKey = anthropic
    }
}
