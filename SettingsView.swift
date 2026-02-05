import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var showOpenAIKey: Bool = false
    @State private var showAnthropicKey: Bool = false
    @State private var showNotionKey: Bool = false
    @State private var isAPIExpanded: Bool = true

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

            Spacer(minLength: 8)
        }
        .padding(.vertical, 8)
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
