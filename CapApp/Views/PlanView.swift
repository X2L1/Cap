import SwiftUI

struct PlanView: View {
    @ObservedObject var chat: ChatViewModel
    @ObservedObject var eventKitService: EventKitService
    @ObservedObject var locationService: LocationService

    @State private var planItems: [PlanItem] = []
    @State private var weights: [String: Int] = LocalStore.shared.loadCourseWeights()
    @State private var briefing: String?
    @State private var isBriefing = false
    @State private var showAddEvent = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        Task { await runBriefing() }
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                            Text(isBriefing ? "Thinking…" : "Brief me")
                            if isBriefing { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isBriefing)
                    if let briefing {
                        Text(briefing).font(.callout)
                    }
                } header: { Text("Briefing") }

                Section {
                    if planItems.isEmpty {
                        Text("Nothing to triage yet — add Canvas in Settings or a task in Today.")
                            .foregroundStyle(.secondary).font(.callout)
                    } else {
                        ForEach(planItems) { item in
                            HStack(spacing: 12) {
                                Circle().fill(color(for: item)).frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).lineLimit(2)
                                    HStack(spacing: 6) {
                                        Text(item.dueDescription)
                                        if let code = item.courseCode { Text("· \(code)") }
                                        Text("· \(item.source.rawValue)")
                                    }
                                    .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: { Text("What to do first") }

                if !courseCodes.isEmpty {
                    Section {
                        ForEach(courseCodes, id: \.self) { code in
                            Stepper(value: binding(for: code), in: 1...5) {
                                HStack {
                                    Text(code)
                                    Spacer()
                                    Text(importanceLabel(weights[code] ?? 3)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: { Text("Course importance") } footer: {
                        Text("The ICS feed can't tell Cap which classes matter most. Set it once and it'll weigh deadlines accordingly.")
                    }
                }

                Section {
                    Button {
                        showAddEvent = true
                    } label: {
                        Label("Add event to Apple Calendar", systemImage: "calendar.badge.plus")
                    }
                    NavigationLink {
                        LeaveByView(locationService: locationService)
                    } label: {
                        Label("When do I need to leave?", systemImage: "location")
                    }
                    NavigationLink {
                        PlacesView(locationService: locationService)
                    } label: {
                        Label("Key places & arrival alerts", systemImage: "mappin.and.ellipse")
                    }
                } header: { Text("Calendar & places") }
            }
            .navigationTitle("Plan")
            .task { await reload() }
            .refreshable { await reload() }
            .sheet(isPresented: $showAddEvent) {
                AddEventSheet(eventKitService: eventKitService)
            }
        }
    }

    private var courseCodes: [String] { Planner.courseCodes(in: chat.canvasItems) }

    private func reload() async {
        await chat.refreshAssignmentsCache()
        recompute()
    }

    private func recompute() {
        planItems = Planner.prioritize(
            canvas: chat.canvasItems,
            tasks: LocalStore.shared.loadTasks(),
            weights: weights
        )
    }

    private func runBriefing() async {
        isBriefing = true
        briefing = await chat.generateBriefing()
        isBriefing = false
    }

    private func binding(for code: String) -> Binding<Int> {
        Binding(
            get: { weights[code] ?? 3 },
            set: {
                weights[code] = $0
                LocalStore.shared.saveCourseWeights(weights)
                recompute()
            }
        )
    }

    private func importanceLabel(_ v: Int) -> String {
        ["", "Low", "Low", "Medium", "High", "Top"][min(max(v, 1), 5)]
    }

    private func color(for item: PlanItem) -> Color {
        switch item.score {
        case 15...: return .red
        case 9..<15: return .orange
        default: return .green
        }
    }
}

/// Minimal create-event form for Apple Calendar write-back.
private struct AddEventSheet: View {
    @ObservedObject var eventKitService: EventKitService
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var start = Date().addingTimeInterval(3600)
    @State private var end = Date().addingTimeInterval(7200)
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                DatePicker("Starts", selection: $start)
                DatePicker("Ends", selection: $end, in: start...)
                if failed {
                    Text("Couldn't save — check calendar access in Settings.")
                        .foregroundStyle(.red).font(.caption)
                }
            }
            .navigationTitle("New Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || end <= start)
                }
            }
        }
    }

    private func save() {
        let ok = eventKitService.createEvent(title: title, start: start, end: end, notes: "Added by Cap")
        if ok { dismiss() } else { failed = true }
    }
}
