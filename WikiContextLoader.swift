import Foundation

// MARK: - 위키 기반 컨텍스트 로더

final class WikiContextLoader {
    static let shared = WikiContextLoader()

    private var cachedContext: String?
    private var cachedPath: String?

    private init() {}

    // MARK: - Public API

    /// 위키 경로에서 컨텍스트를 로드한다. 같은 경로면 캐시를 반환한다.
    func loadContext(from wikiPath: String) -> String? {
        guard !wikiPath.isEmpty else { return nil }

        // 캐시 히트
        if let cached = cachedContext, cachedPath == wikiPath {
            return cached
        }

        // Security-Scoped Bookmark으로 접근 권한 확보
        var scopedURL: URL?
        if let bookmarkURL = SettingsManager.shared.resolveWikiBookmark() {
            if bookmarkURL.startAccessingSecurityScopedResource() {
                scopedURL = bookmarkURL
            }
        }
        defer { scopedURL?.stopAccessingSecurityScopedResource() }

        guard FileManager.default.fileExists(atPath: wikiPath) else {
            print("⚠️ 위키 경로를 찾을 수 없습니다: \(wikiPath)")
            return nil
        }

        var sections: [String] = []

        // 회사 프로필
        if let profile = readFile(wikiPath + "/team/company/rsquare-profile.md") {
            sections.append("## 회사 배경 (위키 기반)\n\(profile)")
        }

        // RTB 시스템 컨텍스트
        if let context = readFile(wikiPath + "/rtb-common/RTB_CONTEXT.md") {
            sections.append("## RTB 시스템 컨텍스트\n\(context)")
        }

        // 도메인 용어사전
        if let glossary = readFile(wikiPath + "/rtb-common/glossary.md") {
            sections.append("## 도메인 용어사전\n\(glossary)")
        }

        guard !sections.isEmpty else {
            print("⚠️ 위키에서 읽을 수 있는 문서가 없습니다.")
            return nil
        }

        let context = sections.joined(separator: "\n\n")
        cachedContext = context
        cachedPath = wikiPath
        print("✅ 위키 컨텍스트 로드 완료 (길이: \(context.count)자)")
        return context
    }

    /// 위키 컨텍스트 유무에 따라 시스템 프롬프트를 생성한다.
    func buildSystemPrompt(wikiContext: String?) -> String {
        if let wikiContext = wikiContext {
            return buildWikiBasedPrompt(wikiContext: wikiContext)
        } else {
            return buildFallbackPrompt()
        }
    }

    /// 캐시를 초기화한다.
    func clearCache() {
        cachedContext = nil
        cachedPath = nil
    }

    // MARK: - Private

    private func readFile(_ path: String) -> String? {
        guard FileManager.default.fileExists(atPath: path) else {
            print("⚠️ 위키 파일을 찾을 수 없습니다: \(path)")
            return nil
        }
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return content
        } catch {
            print("⚠️ 위키 파일 읽기 실패: \(path), \(error.localizedDescription)")
            return nil
        }
    }

    private func buildWikiBasedPrompt(wikiContext: String) -> String {
        return """
당신은 알스퀘어(RSquare) RTB 개발팀의 회의록 전문 정리자입니다.

\(wikiContext)

## 팀원 (이름 언급 시 반드시 @성+이름으로 표기)
- 개발자: @박상용(팀장), @복영균(이사), @양준철(TL), @이종호, @홍채민, @최영기, @조재용, @김민정
- PM(기획): @이미정, @최병선, @서연정
"""
    }

    private func buildFallbackPrompt() -> String {
        return """
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
    }
}
