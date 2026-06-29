import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

enum GoogleAuthError: Error { case noCode, tokenFailed, cancelled }

/// Google OAuth 2.0 for a native iOS app: PKCE, no client secret. The only things that
/// leave the device here are the OAuth calls to Google itself (auth + token + API), using
/// the user's own account. Tokens live in Keychain, this-device-only. Read-only scopes.
@MainActor
final class GoogleAuthService: NSObject, ObservableObject {
    static let clientID = "407694880805-l073efr767eeqqangm60eosii8lukal1.apps.googleusercontent.com"
    static let reversedClientID = "com.googleusercontent.apps.407694880805-l073efr767eeqqangm60eosii8lukal1"
    static let redirectURI = reversedClientID + ":/oauth2redirect"
    static let scopes = [
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/gmail.readonly"
    ]

    @Published var isConnected = false

    private let accessKey = "cap.google.access"
    private let refreshKey = "cap.google.refresh"
    private let expiryKey = "cap.google.expiry"

    private var authSession: ASWebAuthenticationSession?

    override init() {
        super.init()
        isConnected = KeychainStore.read(refreshKey) != nil
    }

    func signIn() async throws {
        let verifier = Self.makeCodeVerifier()
        let challenge = Self.codeChallenge(for: verifier)

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id", value: Self.clientID),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent")
        ]

        let callbackURL = try await authenticate(url: comps.url!)
        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleAuthError.noCode
        }
        try await exchangeCode(code, verifier: verifier)
        isConnected = true
    }

    func signOut() {
        [accessKey, refreshKey, expiryKey].forEach(KeychainStore.delete)
        isConnected = false
    }

    /// A valid access token, refreshing if it's expired/near-expiry. Nil if not connected.
    func validAccessToken() async -> String? {
        guard KeychainStore.read(refreshKey) != nil else { return nil }
        if let token = KeychainStore.read(accessKey),
           let expiryStr = KeychainStore.read(expiryKey),
           let expiry = Double(expiryStr),
           Date().timeIntervalSince1970 < expiry - 60 {
            return token
        }
        return try? await refresh()
    }

    // MARK: - Token exchange / refresh

    private func exchangeCode(_ code: String, verifier: String) async throws {
        let token = try await postToken([
            "code": code,
            "client_id": Self.clientID,
            "redirect_uri": Self.redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier
        ])
        store(token)
    }

    private func refresh() async throws -> String? {
        guard let refreshToken = KeychainStore.read(refreshKey) else { return nil }
        let token = try await postToken([
            "client_id": Self.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])
        store(token, keepRefresh: refreshToken)
        return token.accessToken
    }

    private func postToken(_ body: [String: String]) async throws -> TokenResponse {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .capQueryValue) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw GoogleAuthError.tokenFailed
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func store(_ token: TokenResponse, keepRefresh: String? = nil) {
        KeychainStore.save(token.accessToken, for: accessKey)
        KeychainStore.save(String(Date().timeIntervalSince1970 + Double(token.expiresIn)), for: expiryKey)
        if let refresh = token.refreshToken {
            KeychainStore.save(refresh, for: refreshKey)
        } else if let keepRefresh {
            KeychainStore.save(keepRefresh, for: refreshKey)
        }
    }

    // MARK: - PKCE

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    private static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }

    // MARK: - Web auth session

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: Self.reversedClientID
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? GoogleAuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            authSession = session
            session.start()
        }
    }
}

extension GoogleAuthService: ASWebAuthenticationPresentationContextProviding {
    // Main-actor isolated (the class is @MainActor); the system invokes this on the main
    // thread, so reading UIApplication.shared here is safe.
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension CharacterSet {
    /// Unreserved characters per RFC 3986, so form values (incl. the redirect URI's `:` and
    /// `/`) get percent-encoded correctly.
    static let capQueryValue = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
    )
}
