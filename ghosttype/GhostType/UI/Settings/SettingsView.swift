import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Backend") {
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

                LabeledContent("Accessibility") {
                    if appState.accessibilityGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Button("Grant Access") {
                            AccessibilityEngine.requestPermission()
                        }
                    }
                }

                LabeledContent("Shortcut") {
                    Text("Ctrl + K")
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            Section("Model") {
                LabeledContent("Model ID") {
                    TextField("", text: $appState.modelId)
                }
                Text("e.g. global.anthropic.claude-opus-4-6-v1")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("AWS Credentials") {
                LabeledContent("AWS Profile") {
                    TextField("", text: $appState.awsProfile)
                }
                Text("Leave blank for default credential chain.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                LabeledContent("Region") {
                    Picker("", selection: $appState.awsRegion) {
                        Text("us-west-2 (Oregon)").tag("us-west-2")
                        Text("us-east-1 (N. Virginia)").tag("us-east-1")
                        Text("eu-west-1 (Ireland)").tag("eu-west-1")
                        Text("ap-northeast-1 (Tokyo)").tag("ap-northeast-1")
                        Text("ap-southeast-1 (Singapore)").tag("ap-southeast-1")
                    }
                    .labelsHidden()
                }
            }

            Section("Avatar") {
                Toggle("Show Avatar Panel", isOn: $appState.showAvatarPanel)
                LabeledContent("Avatar URL") {
                    TextField("", text: $appState.avatarURL)
                }
                Text("URL loaded in the avatar panel (WKWebView).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("History") {
                LabeledContent("Saved Sessions") {
                    Text("\(appState.sessionHistory.count)")
                        .foregroundStyle(.secondary)
                }
                if !appState.sessionHistory.isEmpty {
                    Button("Clear All History", role: .destructive) {
                        let ids = appState.sessionHistory.map(\.id)
                        for id in ids {
                            appState.deleteSession(id: id)
                        }
                    }
                }
            }

            Section("Text-to-Speech (MiniMax)") {
                LabeledContent("API Key") {
                    SecureField("", text: $appState.minimaxApiKey)
                }
                Text("Get your API key from minimax.io")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                LabeledContent("Voice") {
                    Picker("", selection: $appState.ttsVoiceId) {
                        Text("Graceful Lady").tag("English_Graceful_Lady")
                        Text("Insightful Speaker").tag("English_Insightful_Speaker")
                        Text("Persuasive Man").tag("English_Persuasive_Man")
                        Text("Lucky Robot").tag("English_Lucky_Robot")
                        Text("Expressive Narrator").tag("English_expressive_narrator")
                    }
                    .labelsHidden()
                }

                LabeledContent("Speed") {
                    HStack {
                        Slider(value: $appState.ttsSpeed, in: 0.5...2.0, step: 0.1)
                            .frame(width: 150)
                        Text(String(format: "%.1fx", appState.ttsSpeed))
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 40)
                    }
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
        .frame(width: 500, height: 750)
    }
}
