import FoundationModels

enum CapModelError: Error {
    case unavailable(String)
}

/// Wraps Apple's on-device Foundation Models framework.
///
/// !! VERIFY BEFORE TRUSTING THIS FILE !!
/// This framework shipped at WWDC25 (iOS 26) and kept evolving — WWDC26 added
/// pluggable model providers. The exact type/method names below (LanguageModelSession,
/// .respond(to:), .content, SystemLanguageModel.default.availability) reflect the
/// documented pattern as of this writing, but Xcode's autocomplete on YOUR installed
/// SDK is the source of truth, not this comment. First thing to do when you open this
/// in Xcode: build this file alone and fix whatever the compiler disagrees with.
actor FoundationModelsService {
    private var session: LanguageModelSession?

    func send(_ message: String, context: String) async throws -> String {
        try checkAvailability()
        let activeSession = session ?? LanguageModelSession(instructions: Persona.systemInstructions)
        session = activeSession

        let prompt = context.isEmpty ? message : "\(context)\n\nUser: \(message)"
        let response = try await activeSession.respond(to: prompt)
        return response.content
    }

    /// One-off prompt on a throwaway session — used for briefings/triage so they don't
    /// pollute the ongoing chat conversation's turn history.
    func oneShot(_ prompt: String, context: String) async throws -> String {
        try checkAvailability()
        let session = LanguageModelSession(instructions: Persona.systemInstructions)
        let full = context.isEmpty ? prompt : "\(context)\n\nUser: \(prompt)"
        return try await session.respond(to: full).content
    }

    /// Drop the session to start a fresh conversation (clears the model's turn history,
    /// not Cap's own chat log in the UI).
    func resetConversation() {
        session = nil
    }

    private func checkAvailability() throws {
        switch SystemLanguageModel.default.availability {
        case .available:
            return
        case .unavailable(let reason):
            throw CapModelError.unavailable("\(reason)")
        @unknown default:
            throw CapModelError.unavailable("unknown")
        }
    }
}
