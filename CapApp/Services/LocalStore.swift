import Foundation

/// JSON-file-backed store for Cap's own task list. Lives in the app's Documents
/// directory (sandboxed to this app, excluded from iCloud by default since we
/// never opt into NSUbiquitousContainer), with complete file-protection applied
/// so the file is encrypted at rest and unreadable before first unlock.
final class LocalStore {
    static let shared = LocalStore()

    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("cap_tasks.json")
    }

    func loadTasks() -> [CapTask] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([CapTask].self, from: data)) ?? []
    }

    func saveTasks(_ tasks: [CapTask]) {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: fileURL.path
        )
    }

    func addTask(_ task: CapTask) {
        var tasks = loadTasks()
        tasks.append(task)
        saveTasks(tasks)
    }

    func toggleDone(id: UUID) {
        var tasks = loadTasks()
        if let idx = tasks.firstIndex(where: { $0.id == id }) {
            tasks[idx].isDone.toggle()
            saveTasks(tasks)
        }
    }
}
