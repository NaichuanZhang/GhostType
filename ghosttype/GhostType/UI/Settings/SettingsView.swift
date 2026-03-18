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

            HStack {
                Spacer()
                Button("Save") {
                    appState.saveSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 500, height: 600)
    }
}
