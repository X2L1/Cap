import SwiftUI

struct SettingsView: View {
    @ObservedObject var eventKitService: EventKitService
    @ObservedObject var contactsService: ContactsService
    @ObservedObject var chat: ChatViewModel

    @State private var feedURL: String = ""
    @State private var domain: String = ""
    @State private var token: String = ""
    @State private var savedConfirmation: String?
    @State private var showTokenPath = false
    @FocusState private var keyboardFocused: Bool
    @AppStorage("cap.briefings.enabled") private var briefingsEnabled = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Read replies aloud", isOn: $chat.speakReplies)
                } header: { Text("Voice") } footer: {
                    Text("Cap speaks answers through whatever earbuds or speaker is active. Tap the mic in chat to talk to it.")
                }

                Section {
                    Toggle("Daily morning & evening briefings", isOn: $briefingsEnabled)
                        .onChange(of: briefingsEnabled) { _, on in
                            Task {
                                if on {
                                    let granted = await NotificationService.shared.requestAuthorization()
                                    if granted {
                                        NotificationService.shared.scheduleBriefings()
                                    } else {
                                        briefingsEnabled = false
                                    }
                                } else {
                                    NotificationService.shared.cancelBriefings()
                                }
                            }
                        }
                } header: { Text("Briefings") } footer: {
                    Text("A 7:30am and 8:00pm reminder that opens straight into your Plan. Scheduled locally — no background process.")
                }

                Section {
                    LabeledContent("Access") {
                        Text(calendarStatusText).foregroundStyle(.secondary)
                    }
                    Button("Request calendar access") {
                        Task { _ = await eventKitService.requestAccess() }
                    }
                    let calendars = eventKitService.availableCalendars()
                    if calendars.isEmpty {
                        Text("Grant access to choose which calendars Cap reads.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(calendars) { cal in
                            Toggle(cal.title, isOn: Binding(
                                get: { !eventKitService.hiddenCalendarIDs.contains(cal.id) },
                                set: { eventKitService.setCalendar(cal.id, enabled: $0) }
                            ))
                        }
                    }
                } header: { Text("Apple Calendar") } footer: {
                    Text("Turn off the shared calendars you don't want Cap to surface.")
                }

                Section {
                    LabeledContent("Access") {
                        Text(contactsStatusText).foregroundStyle(.secondary)
                    }
                    Button("Request contacts access") {
                        Task { _ = await contactsService.requestAccess() }
                    }
                } header: { Text("Contacts") } footer: {
                    Text("Used only to read birthdays so Cap can remind you. Nothing leaves the phone.")
                }

                Section {
                    TextField("Calendar feed URL (.ics)", text: $feedURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($keyboardFocused)
                    Button("Save Canvas feed") { saveFeed() }
                        .disabled(feedURL.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: { Text("Canvas") } footer: {
                    Text("In Canvas on the web: Calendar → \"Calendar Feed\" (bottom-right) → copy the link. This works even if your school blocks access tokens. It carries assignment titles and due dates.")
                }

                Section {
                    DisclosureGroup("Have an access token instead?", isExpanded: $showTokenPath) {
                        TextField("School domain, e.g. yourschool.instructure.com", text: $domain)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($keyboardFocused)
                        SecureField("Personal access token", text: $token)
                            .focused($keyboardFocused)
                        Button("Save token credentials") { saveToken() }
                            .disabled(domain.isEmpty || token.isEmpty)
                    }
                } footer: {
                    Text("Optional richer path — only if your school lets you create a token under Account → Settings → Approved Integrations.")
                }

                if let savedConfirmation {
                    Section {
                        Label(savedConfirmation, systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green).font(.callout)
                    }
                }

                Section("Privacy") {
                    Text("Everything stays on this device except Canvas calls to your school's own domain, and Apple's on-device model, which never leaves the phone. No analytics, no cloud sync, no third party in between.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Button("Done") { keyboardFocused = false }
                    Spacer()
                }
            }
        }
    }

    private var calendarStatusText: String {
        switch eventKitService.authorizationStatus {
        case .fullAccess, .authorized: return "Granted"
        case .denied, .restricted: return "Denied"
        default: return "Not yet asked"
        }
    }

    private var contactsStatusText: String {
        switch contactsService.authorizationStatus {
        case .authorized: return "Granted"
        case .limited: return "Limited"
        case .denied, .restricted: return "Denied"
        default: return "Not yet asked"
        }
    }

    private func saveFeed() {
        let clean = feedURL.trimmingCharacters(in: .whitespaces)
        CanvasService.saveFeedURL(clean)
        savedConfirmation = "Canvas feed saved to Keychain, on this device only."
        feedURL = ""
        Task { await chat.refreshAssignmentsCache() }
    }

    private func saveToken() {
        let cleanDomain = domain
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: .whitespaces)
        CanvasService.saveCredentials(domain: cleanDomain, token: token)
        savedConfirmation = "Canvas token saved to Keychain, on this device only."
        token = ""
        Task { await chat.refreshAssignmentsCache() }
    }
}
