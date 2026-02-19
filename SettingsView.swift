import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var showOpenAIKey: Bool = false
    @State private var showAnthropicKey: Bool = false
    @State private var showNotionKey: Bool = false
    @State private var isAPIExpanded: Bool = true
    @State private var isWikiExpanded: Bool = true

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
                        isVisible: $showOpenAIKey
                    )

                    Divider()

                    apiKeyRow(
                        label: "Anthropic",
                        placeholder: "sk-ant-...",
                        value: $settings.anthropicKey,
                        isVisible: $showAnthropicKey
                    )

                    Divider()

                    apiKeyRow(
                        label: "Notion",
                        placeholder: "ntn_...",
                        value: $settings.notionKey,
                        isVisible: $showNotionKey
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
                        .tint(Color(nsColor: NSColor(red: 0.25, green: 0.25, blue: 0.3, alpha: 1.0)))
                    }
                    .padding(.top, 4)
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
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .windowBackgroundColor))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
                            )

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
                                .foregroundColor(isValid ? .green : .orange)
                            Text(isValid ? "경로 확인됨" : "경로를 찾을 수 없습니다")
                                .font(.system(size: 11))
                                .foregroundColor(isValid ? .green : .orange)
                            Spacer()
                        }
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
        isVisible: Binding<Bool>
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
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
            )
        }
    }
}
