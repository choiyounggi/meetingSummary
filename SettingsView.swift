import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = SettingsManager.shared
    @State private var showOpenAIKey: Bool = false
    @State private var showAnthropicKey: Bool = false

    private let labelWidth: CGFloat = 110
    private let buttonWidth: CGFloat = 68   // "표시"/"숨기기" 여유폭
    private let minFieldWidth: CGFloat = 220
    private let maxFieldWidth: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("설정")
                .font(.title2)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 12) {
                Text("API 키")
                    .font(.headline)

                // OpenAI
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("OpenAI 키")
                        .frame(width: labelWidth, alignment: .leading)

                    // 필드가 남은 공간을 우선 차지하고, 버튼은 항상 보이도록 trailing에 고정
                    if showOpenAIKey {
                        TextField("sk-...", text: $settings.openAIKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(minWidth: minFieldWidth, maxWidth: maxFieldWidth)
                    } else {
                        SecureField("sk-...", text: $settings.openAIKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(minWidth: minFieldWidth, maxWidth: maxFieldWidth)
                    }

                    Spacer(minLength: 8)

                    Button(showOpenAIKey ? "숨기기" : "표시") {
                        showOpenAIKey.toggle()
                    }
                    .frame(width: buttonWidth)
                    .buttonStyle(.bordered)
                }

                // Anthropic
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Anthropic 키")
                        .frame(width: labelWidth, alignment: .leading)

                    if showAnthropicKey {
                        TextField("anthropic-key...", text: $settings.anthropicKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(minWidth: minFieldWidth, maxWidth: maxFieldWidth)
                    } else {
                        SecureField("anthropic-key...", text: $settings.anthropicKey)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                            .frame(minWidth: minFieldWidth, maxWidth: maxFieldWidth)
                    }

                    Spacer(minLength: 8)

                    Button(showAnthropicKey ? "숨기기" : "표시") {
                        showAnthropicKey.toggle()
                    }
                    .frame(width: buttonWidth)
                    .buttonStyle(.bordered)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("저장") {
                    settings.save(openAI: settings.openAIKey, anthropic: settings.anthropicKey)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }
}
