import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var showOpenAIKey: Bool = false
    @State private var showAnthropicKey: Bool = false
    @State private var showNotionKey: Bool = false
    @State private var showGithubToken: Bool = false
    @State private var showHuggingFaceToken: Bool = false
    @State private var isAPIExpanded: Bool = true
    @State private var isWikiExpanded: Bool = true
    @State private var isDiarizationExpanded: Bool = true
    @FocusState private var focusedField: SettingsField?

    // MARK: - 디자인 토큰

    private static let accentIndigo = Color(nsColor: NSColor(red: 0.31, green: 0.27, blue: 0.90, alpha: 1.0))
    private static let successGreen = Color(nsColor: NSColor(red: 0.16, green: 0.72, blue: 0.53, alpha: 1.0))

    private enum SettingsField: Hashable {
        case openAI, anthropic, notion, github, huggingFace
        case pythonPath, wikiPath, wikiRagURL
    }

    var body: some View {
        VStack(spacing: 10) {
            // API 키 카드
            CardSection(
                title: "API 키",
                icon: "key.fill",
                isExpanded: $isAPIExpanded
            ) {
                VStack(spacing: 14) {
                    apiKeyRow(
                        label: "OpenAI",
                        placeholder: "sk-...",
                        value: $settings.openAIKey,
                        isVisible: $showOpenAIKey,
                        field: .openAI
                    )

                    Divider()

                    apiKeyRow(
                        label: "Anthropic",
                        placeholder: "sk-ant-...",
                        value: $settings.anthropicKey,
                        isVisible: $showAnthropicKey,
                        field: .anthropic
                    )

                    Divider()

                    apiKeyRow(
                        label: "Notion",
                        placeholder: "ntn_...",
                        value: $settings.notionKey,
                        isVisible: $showNotionKey,
                        field: .notion
                    )

                    Divider()

                    apiKeyRow(
                        label: "GitHub",
                        placeholder: "ghp_...",
                        value: $settings.githubToken,
                        isVisible: $showGithubToken,
                        field: .github
                    )

                    // 저장 버튼
                    HStack {
                        Spacer()
                        Button {
                            settings.save(
                                openAI: settings.openAIKey,
                                anthropic: settings.anthropicKey,
                                notion: settings.notionKey
                            )
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11))
                                Text("저장")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Self.accentIndigo)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 16)

            // 화자 분리 카드
            CardSection(
                title: "화자 분리",
                icon: "person.2.fill",
                isExpanded: $isDiarizationExpanded
            ) {
                VStack(spacing: 12) {
                    // 모드 선택
                    Picker("", selection: $settings.diarizationMode) {
                        ForEach(DiarizationMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    // 모드 설명
                    Text(settings.diarizationMode.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // pyannote 모드일 때만 추가 설정 노출
                    if settings.diarizationMode == .pyannote {
                        Divider()

                        apiKeyRow(
                            label: "HuggingFace Token",
                            placeholder: "hf_...",
                            value: $settings.huggingFaceToken,
                            isVisible: $showHuggingFaceToken,
                            field: .huggingFace
                        )

                        Divider()

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Python 경로")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            TextField("/opt/homebrew/bin/python3", text: $settings.pythonPath)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(nsColor: .windowBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(
                                            focusedField == .pythonPath
                                                ? Self.accentIndigo.opacity(0.5)
                                                : Color(nsColor: .separatorColor).opacity(0.2),
                                            lineWidth: focusedField == .pythonPath ? 1.0 : 0.5
                                        )
                                )
                                .focused($focusedField, equals: .pythonPath)

                            Text("pyannote + torch가 설치된 Python 경로")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)

            // 위키 경로 카드
            CardSection(
                title: "위키 경로",
                icon: "book.fill",
                isExpanded: $isWikiExpanded
            ) {
                VStack(spacing: 10) {
                    Text("회의록 요약 시 위키 문서를 컨텍스트로 활용합니다.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 8) {
                        TextField("위키 폴더 경로", text: $settings.wikiPath)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .windowBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(
                                        focusedField == .wikiPath
                                            ? Self.accentIndigo.opacity(0.5)
                                            : Color(nsColor: .separatorColor).opacity(0.2),
                                        lineWidth: focusedField == .wikiPath ? 1.0 : 0.5
                                    )
                            )
                            .focused($focusedField, equals: .wikiPath)

                        Button {
                            selectWikiFolder()
                        } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 13))
                        }
                        .buttonStyle(.bordered)
                    }

                    if !settings.wikiPath.isEmpty {
                        let isValid = FileManager.default.fileExists(atPath: settings.wikiPath)
                        HStack(spacing: 4) {
                            Image(systemName: isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(isValid ? Self.successGreen : .orange)
                            Text(isValid ? "경로 확인됨" : "경로를 찾을 수 없습니다")
                                .font(.system(size: 11))
                                .foregroundColor(isValid ? Self.successGreen : .orange)
                            Spacer()
                        }
                    }

                    Divider()

                    // Wiki-RAG 서버 URL
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Wiki-RAG 서버")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        TextField("http://localhost:8686", text: $settings.wikiRagURL)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(nsColor: .windowBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(
                                        focusedField == .wikiRagURL
                                            ? Self.accentIndigo.opacity(0.5)
                                            : Color(nsColor: .separatorColor).opacity(0.2),
                                        lineWidth: focusedField == .wikiRagURL ? 1.0 : 0.5
                                    )
                            )
                            .focused($focusedField, equals: .wikiRagURL)

                        Text("시맨틱 검색 기반 위키 컨텍스트 서버 URL")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 8)
        }
        .padding(.vertical, 8)
    }

    private func selectWikiFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "위키 폴더를 선택하세요"
        panel.prompt = "선택"

        if panel.runModal() == .OK, let url = panel.url {
            settings.saveWikiBookmark(for: url)
        }
    }

    @ViewBuilder
    private func apiKeyRow(
        label: String,
        placeholder: String,
        value: Binding<String>,
        isVisible: Binding<Bool>,
        field: SettingsField
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    isVisible.wrappedValue.toggle()
                } label: {
                    Image(systemName: isVisible.wrappedValue ? "eye.slash" : "eye")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Group {
                if isVisible.wrappedValue {
                    TextField(placeholder, text: value)
                } else {
                    SecureField(placeholder, text: value)
                }
            }
            .textFieldStyle(.plain)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        focusedField == field
                            ? Self.accentIndigo.opacity(0.5)
                            : Color(nsColor: .separatorColor).opacity(0.2),
                        lineWidth: focusedField == field ? 1.0 : 0.5
                    )
            )
            .focused($focusedField, equals: field)
        }
    }
}
