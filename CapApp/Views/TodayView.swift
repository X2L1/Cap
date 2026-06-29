import SwiftUI

struct TodayView: View {
    @ObservedObject var eventKitService: EventKitService
    @State private var assignments: [CanvasAssignment] = []
    @State private var newTaskTitle = ""
    @State private var tasks: [CapTask] = LocalStore.shared.loadTasks()

    private let canvasService = CanvasService()

    var body: some View {
        NavigationStack {
            List {
                Section("Calendar — next 7 days") {
                    let events = eventKitService.upcomingEvents(daysAhead: 7)
                    if events.isEmpty {
                        Text("Nothing on the calendar, or access not granted yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(events) { event in
                            VStack(alignment: .leading) {
                                Text(event.title)
                                Text(event.start.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Canvas — next 14 days") {
                    if !CanvasService.hasCredentials {
                        Text("Add your Canvas domain and token in Settings.")
                            .foregroundStyle(.secondary)
                    } else if assignments.isEmpty {
                        Text("Nothing due, or still loading.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(assignments) { assignment in
                            VStack(alignment: .leading) {
                                Text(assignment.name)
                                if let due = assignment.dueDate {
                                    Text("Due \(due.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Quick capture") {
                    HStack {
                        TextField("New task or reminder", text: $newTaskTitle)
                        Button("Add") {
                            addTask()
                        }
                        .disabled(newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ForEach(tasks) { task in
                        Button {
                            LocalStore.shared.toggleDone(id: task.id)
                            tasks = LocalStore.shared.loadTasks()
                        } label: {
                            HStack {
                                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                Text(task.title)
                                    .strikethrough(task.isDone)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Today")
            .task { await initialLoad() }
            .refreshable { await refreshAssignments() }
        }
    }

    private func addTask() {
        let task = CapTask(title: newTaskTitle)
        LocalStore.shared.addTask(task)
        tasks = LocalStore.shared.loadTasks()
        newTaskTitle = ""
    }

    private func initialLoad() async {
        _ = await eventKitService.requestAccess()
        await refreshAssignments()
    }

    private func refreshAssignments() async {
        guard CanvasService.hasCredentials else { return }
        assignments = (try? await canvasService.fetchAllUpcomingAssignments()) ?? []
    }
}
