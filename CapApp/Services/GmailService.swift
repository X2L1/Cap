import Foundation

/// Lightweight inbox metadata for the triage view. Read-only — Cap never sends anything.
struct GmailMessageMeta: Identifiable {
    let id: String
    let from: String
    let subject: String
    let snippet: String
    let date: String
}

/// Reads recent inbox messages via the Gmail v1 API (metadata + snippet only — we never
/// pull full bodies we don't need, and never send).
final class GmailService {
    func recentMessages(auth: GoogleAuthService, max: Int = 15) async -> [GmailMessageMeta] {
        guard let token = await auth.validAccessToken() else { return [] }

        var listComps = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        listComps.queryItems = [
            .init(name: "maxResults", value: String(max)),
            .init(name: "q", value: "in:inbox")
        ]
        var listReq = URLRequest(url: listComps.url!)
        listReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: listReq),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let list = try? JSONDecoder().decode(GmailList.self, from: data) else {
            return []
        }

        var results: [GmailMessageMeta] = []
        for ref in list.messages ?? [] {
            if let meta = await fetchMessage(ref.id, token: token) { results.append(meta) }
        }
        return results
    }

    private func fetchMessage(_ id: String, token: String) async -> GmailMessageMeta? {
        var comps = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)")!
        comps.queryItems = [
            .init(name: "format", value: "metadata"),
            .init(name: "metadataHeaders", value: "From"),
            .init(name: "metadataHeaders", value: "Subject"),
            .init(name: "metadataHeaders", value: "Date")
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let message = try? JSONDecoder().decode(GmailMessage.self, from: data) else {
            return nil
        }
        let headers = message.payload?.headers ?? []
        func header(_ name: String) -> String {
            headers.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value ?? ""
        }
        return GmailMessageMeta(
            id: id,
            from: header("From"),
            subject: header("Subject"),
            snippet: message.snippet ?? "",
            date: header("Date")
        )
    }
}

private struct GmailList: Decodable { let messages: [GmailRef]? }
private struct GmailRef: Decodable { let id: String }
private struct GmailMessage: Decodable { let snippet: String?; let payload: GmailPayload? }
private struct GmailPayload: Decodable { let headers: [GmailHeader]? }
private struct GmailHeader: Decodable { let name: String; let value: String }
