import SwiftUI

struct TodayView: View {
    @ObservedObject var eventKitService: EventKitService
    @ObservedObject var contactsService: ContactsService
    @State private var assignments: [CanvasItem] = []
    @State private var birthdays: [Birthday] = []
    @State private var newTaskTitle = ""
    @State private var tasks: [CapTask] = LocalStore.shared.loadTasks()

    private let canvasService = CanvasService()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let events = eventKitService.upcomingEvents(daysAhead: 7)
                    if events.isEmpty {
                        emptyRow("Nothing on the calendar, or access not granted yet.")
                    } else {
                        ForEach(events) { event in
                            row(icon: "calendar", tint: .orange, title: event.title,
                                subtitle: event.start.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                } header: { sectionHeader("Calendar", "next 7 days") }

                Section {
                    if !CanvasService.hasCredentials {
                        emptyRow("Add your Canvas calendar feed in Settings.")
                    } else if assignments.isEmpty {
                        emptyRow("Nothing due, or still loading.")
                    } else {
                        ForEach(assignments) { item in
                            row(icon: "doc.text", tint: Theme.accent, title: item.name,
                                subtitle: item.dueDate.map { "Due \($0.formatted(date: .abbreviated, time: .shortened))" })
                        }
                    }
                } header: { sectionHeader("Canvas", "next 14 days") }

                if !birthdays.isEmpty {
                    Section {
                        ForEach(birthdays) { b in
                            let when = b.daysAway == 0 ? "Today" : b.date.formatted(date: .abbreviated, time: .omitted)
                            row(icon: "gift", tint: .pink, title: b.name + (b.age.map { " (turns \($0))" } ?? ""),
                                subtitle: when)
                        }
                    } header: { sectionHeader("Birthdays", "next 30 days") }
                }

                Section {
                    HStack {
                        TextField("New task or reminder", text: $newTaskTitle)
                        Button("Add") { addTask() }
                            .disabled(newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ForEach(tasks) { task in
                        Button {
                            LocalStore.shared.toggleDone(id: task.id)
                            tasks = LocalStore.shared.loadTasks()
                        } label: {
                            HStack {
                                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.isDone ? Theme.accent : .secondary)
                                Text(task.title).strikethrough(task.isDone)
                                    .foregroundStyle(task.isDone ? .secondary : .primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: { sectionHeader("Quick capture", nil) }
            }
            .navigationTitle("Today")
            .task { await initialLoad() }
            .refreshable { await reload() }
        }
    }

    // MARK: - Rows

    private func sectionHeader(_ title: String, _ trailing: String?) -> some View {
        HStack {
            Text(title)
            if let trailing {
                Spacer()
                Text(trailing).foregroundStyle(.tertiary).textCase(nil)
            }
        }
    }

    private func row(icon: String, tint: Color, title: String, subtitle: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).font(.callout)
    }

    // MARK: - Actions

    private func addTask() {
        LocalStore.shared.addTask(CapTask(title: newTaskTitle))
        tasks = LocalStore.shared.loadTasks()
        newTaskTitle = ""
    }

    private func initialLoad() async {
        _ = await eventKitService.requestAccess()
        _ = await contactsService.requestAccess()
        await reload()
    }

    private func reload() async {
        if CanvasService.hasCredentials {
            assignments = (try? await canvasService.fetchAllUpcomingItems()) ?? []
        }
        birthdays = contactsService.upcomingBirthdays(daysAhead: 30)
    }
}
