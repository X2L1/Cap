import Foundation

/// JSON-file-backed store for Cap's own task list. Lives in the app's Documents
/// directory (sandboxed to this app, excluded from iCloud by default since we
/// never opt into NSUbiquitousContainer), with complete file-protection applied
/// so the file is encrypted at rest and unreadable before first unlock.
final class LocalStore {
    static let shared = LocalStore()

    private let fileURL: URL
    private let chatURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = dir.appendingPathComponent("cap_tasks.json")
        chatURL = dir.appendingPathComponent("cap_chat.json")
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

    // MARK: - Chat history

    func loadMessages() -> [ChatMessage] {
        guard let data = try? Data(contentsOf: chatURL) else { return [] }
        return (try? JSONDecoder().decode([ChatMessage].self, from: data)) ?? []
    }

    /// Persist the chat log so the conversation survives an app relaunch. Capped to the
    /// most recent `keep` messages so the file (and the history we replay into the model)
    /// stays bounded.
    func saveMessages(_ messages: [ChatMessage], keep: Int = 50) {
        let trimmed = Array(messages.suffix(keep))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        try? data.write(to: chatURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: chatURL.path
        )
    }
}
