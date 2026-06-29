import SwiftUI

struct SettingsView: View {
    @ObservedObject var eventKitService: EventKitService
    @State private var domain: String = ""
    @State private var token: String = ""
    @State private var savedConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Calendar") {
                    Button("Request calendar access") {
                        Task { _ = await eventKitService.requestAccess() }
                    }
                    Text("Status: \(String(describing: eventKitService.authorizationStatus))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Canvas") {
                    TextField("School domain, e.g. yourschool.instructure.com", text: $domain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Personal access token", text: $token)
                    Button("Save Canvas credentials") {
                        saveCanvasCredentials()
                    }
                    .disabled(domain.isEmpty || token.isEmpty)
                    if savedConfirmation {
                        Text("Saved to Keychain, on this device only.")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    Text("Get a token in Canvas: Account → Settings → Approved Integrations → New Access Token.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Privacy") {
                    Text("Everything stays on this device except: Canvas API calls to your school's own domain, and Apple's on-device model, which never leaves the phone. No analytics, no cloud sync of your data, no third party in between.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func saveCanvasCredentials() {
        let cleanDomain = domain
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: .whitespaces)
        CanvasService.saveCredentials(domain: cleanDomain, token: token)
        savedConfirmation = true
    }
}
