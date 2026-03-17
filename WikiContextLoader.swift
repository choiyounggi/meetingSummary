import Foundation

// MARK: - 위키 기반 컨텍스트 로더

final class WikiContextLoader {
    static let shared = WikiContextLoader()

    private var cachedContext: String?
    private var cachedPath: String?
    private var cachedSemanticContext: String?

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

    /// wiki-rag HTTP API를 통해 시맨틱 검색 기반 컨텍스트를 조회한다.
    /// 서버 연결 실패 시 completion(nil)을 반환하므로, 호출자가 기존 loadContext 폴백을 사용할 수 있다.
    func searchContext(query: String, completion: @escaping (String?) -> Void) {
        let baseURL = SettingsManager.shared.wikiRagURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !baseURL.isEmpty, let url = URL(string: "\(baseURL)/api/context") else {
            print("⚠️ wiki-rag URL이 유효하지 않습니다: \(baseURL)")
            completion(nil)
            return
        }

        // 쿼리 앞 500자만 사용
        let truncatedQuery = String(query.prefix(500))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10 // 서버 미실행 시 빠르게 실패

        let body: [String: Any] = ["query": truncatedQuery, "limit": 5]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("⚠️ wiki-rag 요청 직렬화 실패: \(error.localizedDescription)")
            completion(nil)
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else {
                completion(nil)
                return
            }

            if let error = error {
                print("⚠️ wiki-rag 서버 연결 실패: \(error.localizedDescription)")
                completion(nil)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("⚠️ wiki-rag 서버 응답 오류 (HTTP \(statusCode))")
                completion(nil)
                return
            }

            guard let data = data else {
                print("⚠️ wiki-rag 응답 데이터가 비어있습니다.")
                completion(nil)
                return
            }

            let contextString = self.parseSearchResponse(data: data)
            if let contextString = contextString {
                self.cachedSemanticContext = contextString
                print("✅ wiki-rag 시맨틱 검색 컨텍스트 로드 완료 (길이: \(contextString.count)자)")
            }
            completion(contextString)
        }.resume()
    }

    /// 캐시를 초기화한다.
    func clearCache() {
        cachedContext = nil
        cachedPath = nil
        cachedSemanticContext = nil
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

    // MARK: - wiki-rag 응답 파싱

    /// wiki-rag API 응답 JSON을 파싱하여 컨텍스트 문자열로 조합한다.
    private func parseSearchResponse(data: Data) -> String? {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("⚠️ wiki-rag 응답 JSON 파싱 실패")
                return nil
            }

            var sections: [String] = []

            // 용어사전
            if let glossary = json["glossary"] as? String,
               !glossary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sections.append("## 도메인 용어사전\n\(glossary)")
            }

            // 시맨틱 검색 결과
            if let results = json["results"] as? [[String: Any]], !results.isEmpty {
                var resultSections: [String] = []
                for result in results {
                    let title = result["title"] as? String ?? "제목 없음"
                    let content = result["content"] as? String ?? ""
                    guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    resultSections.append("### \(title)\n\(content)")
                }
                if !resultSections.isEmpty {
                    sections.append("## 관련 위키 문서 (시맨틱 검색)\n\(resultSections.joined(separator: "\n\n"))")
                }
            }

            guard !sections.isEmpty else {
                print("⚠️ wiki-rag 응답에 유효한 컨텍스트가 없습니다.")
                return nil
            }

            return sections.joined(separator: "\n\n")
        } catch {
            print("⚠️ wiki-rag 응답 파싱 오류: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - STT 보정 사전 (위키/폴백 공통)

    private let sttCorrectionDictionary = """
## STT 음성인식 보정 사전
아래는 음성인식(STT)에서 자주 오인식되는 용어 매핑입니다. 원문에서 왼쪽 표현이 나오면 반드시 오른쪽 정확한 표기로 보정하세요.

### 회사·서비스명
| STT 오인식 (예시) | 정확한 표기 |
|---|---|
| 알스캐어, 알에스퀘어, 알스퀘, 알 스퀘어 | 알스퀘어(RSquare) |
| 알스캐어온, 알스퀘온, 알에스퀘어 온 | 알스퀘어온(rsquareon) |
| 알투비, 아르티비, 알 투 비, 아르 티 비 | RTB |
| 매니지, 매니저(백엔드 문맥) | manage(RTB 백엔드) |
| 매니지 에프이, 매니지 프론트 | manage-fe(RTB 프론트엔드) |

### 기술 용어
| STT 오인식 (예시) | 정확한 표기 |
|---|---|
| 네스트, 넥스트(백엔드 문맥) | NestJS |
| 넉스트, 뉙스트(프론트 문맥) | Nuxt |
| 스프링부트, 스프링 부트 | Spring Boot |
| 포스트그레스, 포스그레, 포스트 그레 | PostgreSQL |
| 이케이에스, EKS | AWS EKS |
| 쿼리파이, 쿼리 파이 | QueryPie |
| 인트 환경, 인트(환경 문맥) | INT(개발환경) |
| 스테이징, 에스티지 | STG(스테이징) |
| 프로덕션, 피알디 | PRD(운영) |

### 도메인 핵심 엔티티
| STT 오인식 (예시) | 정확한 표기 |
|---|---|
| 빌딩(부동산 문맥) | Building(건물) |
| 유닛, 유니트 | Unit(호실) |
| 프로덕트, 프러덕트(매물 문맥) | Product(매물) |
| 딜(영업 문맥) | Deal(딜/거래) |
| 클라이언트(거래처 문맥) | Client(거래처) |
| 커스터머(고객 문맥) | Customer(담당자) |
| 레서, 레설(임대인 문맥) | Lessor(임대인) |
| 레시, 레씨(임차인 문맥) | Lessee(임차인) |
| 피엔유, 피앤유 | PNU(필지고유번호) |
| 지에프에이, GFA | GFA(연면적) |
| 엔엘에이, NLA | NLA(전용면적) |
| 렌트프리, 렌트 프리 | 렌트프리(rent_free) |

### 테이블/컬럼 접두어
| STT 오인식 (예시) | 정확한 표기 |
|---|---|
| 오브제, obj | obj_(객체 테이블) |
| 피알디 테이블 | prd_(매물 테이블) |
| 엠비알 | mbr_(회원 테이블) |
| 지티디 | gtd_(딜 관리 테이블) |
| 씨엘엔 | cln_(거래처 테이블) |

### 보정 예시 (Before → After)
- "알스캐어온에서 빌딩 프로덕트 조회하는 API" → "알스퀘어온에서 Building Product 조회하는 API"
- "매니지에서 피알디 테이블 쿼리파이로 확인" → "manage에서 prd_ 테이블 QueryPie로 확인"
- "인트 환경에 커스터머 딜 플로 테스트" → "INT 환경에 Customer 딜 플로우 테스트"
- "상용님이 포스트그레스 마이그레이션 담당" → "@박상용이 PostgreSQL 마이그레이션 담당"
- "넉스트 프론트에서 유닛 상세 화면 작업" → "Nuxt 프론트에서 Unit 상세 화면 작업"
- "영기가 네스트 API 엔드포인트 추가" → "@최영기가 NestJS API 엔드포인트 추가"
"""

    // MARK: - 팀원 정보 (위키/폴백 공통)

    private let teamMembers = """
## 팀원 (이름 언급 시 반드시 @성+이름으로 표기)
- 개발자: @박상용(팀장), @복영균(이사), @양준철(TL), @이종호, @홍채민, @최영기, @조재용, @김민정
- PM(기획): @이미정, @최병선, @서연정

### 팀원 이름 STT 보정
| STT 인식 | 정확한 표기 |
|---|---|
| 상용, 상용님, 박상용 | @박상용 |
| 영균, 영균님, 복영균 | @복영균 |
| 준철, 준철님, 양준철 | @양준철 |
| 종호, 종호님, 이종호 | @이종호 |
| 채민, 채민님, 홍채민 | @홍채민 |
| 영기, 영기님, 최영기 | @최영기 |
| 재용, 재용님, 조재용 | @조재용 |
| 민정, 민정님, 김민정 | @김민정 |
| 미정, 미정님, 이미정 | @이미정 |
| 병선, 병선님, 최병선 | @최병선 |
| 연정, 연정님, 서연정 | @서연정 |
"""

    private func buildWikiBasedPrompt(wikiContext: String) -> String {
        return """
당신은 알스퀘어(RSquare) RTB 개발팀의 회의록 전문 정리자입니다.

아래 위키 문서는 이번 회의와 관련된 도메인 지식입니다. 용어, 엔티티 관계, 업무 맥락을 파악하여 정확한 회의록을 작성하는 데 참고하세요.

\(wikiContext)

\(sttCorrectionDictionary)

\(teamMembers)
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
- Building(건물) → Unit(호실) → Product(매물) → Deal(딜/거래): 핵심 엔티티 계층 구조
- Client(거래처): 임대인/매도인 (매물 제공자)
- Customer(고객): 임차인/매수인 (매물 수요자)
- PNU: 필지고유번호
- 알스퀘어온(rsquareon): 서비스 도메인
- 딜 플로우: 상담 → 투어 → 협상 → 계약
- 테이블 prefix: obj_(객체), prd_(상품), mbr_(멤버), gtd_(거래), cmm_(공통), sys_(시스템)
- QueryPie: 운영 DB 접근 도구

\(sttCorrectionDictionary)

\(teamMembers)
"""
    }
}
