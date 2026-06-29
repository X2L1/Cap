import Foundation

/// Config for an optional user-run LLM server (Ollama, or anything OpenAI-compatible) on
/// the user's own hardware. The endpoint/model aren't secrets, so they live in UserDefaults.
enum HomeServerConfig {
    static let enabledKey = "cap.homeserver.enabled"
    static let endpointKey = "cap.homeserver.endpoint"
    static let modelKey = "cap.homeserver.model"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var endpoint: String {
        (UserDefaults.standard.string(forKey: endpointKey) ?? "")
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
    static var model: String {
        let m = (UserDefaults.standard.string(forKey: modelKey) ?? "").trimmingCharacters(in: .whitespaces)
        return m.isEmpty ? "llama3.1" : m
    }
}

enum HomeServerError: Error { case notConfigured, badResponse(Int), noContent }

/// Sends chat to the user's own machine — data goes only to the endpoint they configured,
/// not to any third party. Used as a smarter alternative to the on-device model when the
/// user has a server running and reachable; Cap falls back to on-device if it's not.
final class HomeServerService {
    struct Message { let role: String; let content: String }

    /// Cheap reachability probe (used for the "Test connection" button and routing).
    func isReachable() async -> Bool {
        guard !HomeServerConfig.endpoint.isEmpty,
              let url = URL(string: HomeServerConfig.endpoint + "/v1/models") else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        guard let (_, response) = try? await URLSession.shared.data(for: req) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func send(_ messages: [Message]) async throws -> String {
        guard HomeServerConfig.isEnabled, !HomeServerConfig.endpoint.isEmpty,
              let url = URL(string: HomeServerConfig.endpoint + "/v1/chat/completions") else {
            throw HomeServerError.notConfigured
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": HomeServerConfig.model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": false
        ])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw HomeServerError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content else { throw HomeServerError.noContent }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct OpenAIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Msg: Decodable { let content: String }
        let message: Msg
    }
    let choices: [Choice]
}
