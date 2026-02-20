import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Status") {
                HStack {
                    Text("Backend")
                    Spacer()
                    switch appState.backendStatus {
                    case .running:
                        Label("Running", systemImage: "circle.fill")
                            .foregroundColor(.green)
                    case .stopped:
                        Label("Stopped", systemImage: "circle.fill")
                            .foregroundColor(.red)
                    case .error(let msg):
                        Label(msg, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }
                }

                HStack {
                    Text("Accessibility")
                    Spacer()
                    if appState.accessibilityGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Button("Grant Access") {
                            AccessibilityEngine.requestPermission()
                        }
                    }
                }

                HStack {
                    Text("Shortcut")
                    Spacer()
                    Text("Ctrl + K")
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            Section("Backend") {
                Picker("Mode", selection: $appState.backendMode) {
                    Text("Local").tag("local")
                    Text("AgentCore").tag("agentcore")
                }
                .pickerStyle(.segmented)

                if appState.backendMode == "agentcore" {
                    TextField("AgentCore Endpoint URL", text: $appState.agentCoreEndpoint)
                        .textFieldStyle(.roundedBorder)
                    Text("HTTP URL to your AgentCore backend (e.g. http://host:8080)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Model") {
                TextField("Model ID", text: $appState.modelId)
                    .textFieldStyle(.roundedBorder)
                Text("e.g. global.anthropic.claude-opus-4-6-v1")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("AWS Credentials") {
                TextField("AWS Profile", text: $appState.awsProfile)
                    .textFieldStyle(.roundedBorder)
                Text("Leave blank for default credential chain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Region")
                    Spacer()
                    Picker("", selection: $appState.awsRegion) {
                        Text("us-west-2 (Oregon)").tag("us-west-2")
                        Text("us-east-1 (N. Virginia)").tag("us-east-1")
                        Text("eu-west-1 (Ireland)").tag("eu-west-1")
                        Text("ap-northeast-1 (Tokyo)").tag("ap-northeast-1")
                        Text("ap-southeast-1 (Singapore)").tag("ap-southeast-1")
                    }
                    .frame(width: 220)
                }
            }

            Section("Text-to-Speech (MiniMax)") {
                SecureField("API Key", text: $appState.minimaxApiKey)
                    .textFieldStyle(.roundedBorder)
                Text("Get your API key from minimax.io")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text("Voice")
                    Spacer()
                    Picker("", selection: $appState.ttsVoiceId) {
                        Text("Graceful Lady").tag("English_Graceful_Lady")
                        Text("Insightful Speaker").tag("English_Insightful_Speaker")
                        Text("Persuasive Man").tag("English_Persuasive_Man")
                        Text("Lucky Robot").tag("English_Lucky_Robot")
                        Text("Expressive Narrator").tag("English_expressive_narrator")
                    }
                    .frame(width: 200)
                }
                HStack {
                    Text("Speed")
                    Spacer()
                    Slider(value: $appState.ttsSpeed, in: 0.5...2.0, step: 0.1)
                        .frame(width: 150)
                    Text(String(format: "%.1fx", appState.ttsSpeed))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 40)
                }
            }

            HStack {
                Spacer()
                Button("Save") {
                    appState.saveSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 420, height: 620)
    }
}
