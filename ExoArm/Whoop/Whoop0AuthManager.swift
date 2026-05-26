import Foundation
import Combine
import AppKit
import AuthenticationServices
import Security

// manages the Whoop OAuth lifecycle
// authorization, token exchange, secure storage, refresh in that order solider

@MainActor
final class WhoopOAuthManager: NSObject, ObservableObject {
    
    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var lastError: String?
    
    private var authSession: ASWebAuthenticationSession?
    private let keychain = WhoopKeychain()
    
    override init() {
        super.init()
        isAuthorized = keychain.hasValidTokens()
    }
    
    // start OAuth flow. (should) present Whoop login in an in-app browser
    func authorize() async throws {
        let state = Self.randomState(length: 16)
        guard let url = buildAuthURL(state: state) else {
            throw WhoopOAuthError.invalidConfig
        }
        
        let callbackURL: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: WhoopConfig.redirectScheme
            ) { callbackURL, error in
                if let error = error {
                    cont.resume(throwing: error)
                } else if let callbackURL = callbackURL {
                    cont.resume(returning: callbackURL)
                } else {
                    cont.resume(throwing: WhoopOAuthError.noCallback)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            if !session.start() {
                cont.resume(throwing: WhoopOAuthError.invalidConfig)
            }
        }
        
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value else {
            throw WhoopOAuthError.invalidCallback
        }
        
        guard returnedState == state else {
            throw WhoopOAuthError.stateMismatch
        }
        
        let tokens = try await exchangeCodeForTokens(code: code)
        try keychain.store(tokens: tokens)
        isAuthorized = true
        lastError = nil
    }
    
    // returns a valid access token, refreshing if needed.
    func currentAccessToken() async throws -> String {
        guard let stored = keychain.loadTokens() else {
            throw WhoopOAuthError.notAuthorized
        }
        if stored.expiresAt.timeIntervalSinceNow < 60 {
            return try await refreshTokens()
        }
        return stored.accessToken
    }
    
    func logout() {
        keychain.clear()
        isAuthorized = false
    }
    
    private func buildAuthURL(state: String) -> URL? {
        var components = URLComponents(string: WhoopConfig.authURL)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: WhoopConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: WhoopConfig.redirectURI),
            URLQueryItem(name: "scope", value: WhoopConfig.scopeString),
            URLQueryItem(name: "state", value: state)
        ]
        return components?.url
    }
    
    private func exchangeCodeForTokens(code: String) async throws -> StoredTokens {
        guard let url = URL(string: WhoopConfig.tokenURL) else {
            throw WhoopOAuthError.invalidConfig
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": WhoopConfig.redirectURI,
            "client_id": WhoopConfig.clientID,
            "client_secret": WhoopConfig.clientSecret
        ]
        request.httpBody = Self.formEncode(bodyParams).data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WhoopOAuthError.tokenExchangeFailed
        }
        
        let decoded = try JSONDecoder().decode(WhoopTokenResponse.self, from: data)
        return StoredTokens(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken ?? "",
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expiresIn))
        )
    }
    
    private func refreshTokens() async throws -> String {
        guard let stored = keychain.loadTokens(), !stored.refreshToken.isEmpty else {
            throw WhoopOAuthError.notAuthorized
        }
        guard let url = URL(string: WhoopConfig.tokenURL) else {
            throw WhoopOAuthError.invalidConfig
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": stored.refreshToken,
            "client_id": WhoopConfig.clientID,
            "client_secret": WhoopConfig.clientSecret,
            "scope": "offline"
        ]
        request.httpBody = Self.formEncode(bodyParams).data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            keychain.clear()
            isAuthorized = false
            throw WhoopOAuthError.refreshFailed
        }
        
        let decoded = try JSONDecoder().decode(WhoopTokenResponse.self, from: data)
        let newTokens = StoredTokens(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken ?? stored.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(decoded.expiresIn))
        )
        try keychain.store(tokens: newTokens)
        return newTokens.accessToken
    }
    
    private static func randomState(length: Int) -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
        return String((0..<length).map { _ in chars.randomElement()! })
    }
    
    private static func formEncode(_ params: [String: String]) -> String {
        params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }
}

extension WhoopOAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow()
    }
}

enum WhoopOAuthError: Error, LocalizedError {
    case invalidConfig
    case noCallback
    case invalidCallback
    case stateMismatch
    case tokenExchangeFailed
    case refreshFailed
    case notAuthorized
    
    var errorDescription: String? {
        switch self {
        case .invalidConfig: return "Whoop configuration is invalid. Check WhoopConfig values."
        case .noCallback: return "No callback received from Whoop login."
        case .invalidCallback: return "Whoop callback was malformed."
        case .stateMismatch: return "OAuth state mismatch. Possible CSRF attempt."
        case .tokenExchangeFailed: return "Failed to exchange authorization code for tokens."
        case .refreshFailed: return "Failed to refresh access token. Re-authorization needed."
        case .notAuthorized: return "Not authorized with Whoop. Run authorization flow first."
        }
    }
}

struct StoredTokens {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

final class WhoopKeychain {
    
    private let service = "com.pitcherrehab.whoop"
    private let account = "oauth_tokens"
    
    func store(tokens: StoredTokens) throws {
        let payload: [String: Any] = [
            "access_token": tokens.accessToken,
            "refresh_token": tokens.refreshToken,
            "expires_at": tokens.expiresAt.timeIntervalSince1970
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            throw WhoopOAuthError.tokenExchangeFailed
        }
    }
    
    func loadTokens() -> StoredTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = payload["access_token"] as? String,
              let refresh = payload["refresh_token"] as? String,
              let expiresAt = payload["expires_at"] as? TimeInterval else {
            return nil
        }
        
        return StoredTokens(
            accessToken: access,
            refreshToken: refresh,
            expiresAt: Date(timeIntervalSince1970: expiresAt)
        )
    }
    
    func hasValidTokens() -> Bool {
        guard let tokens = loadTokens() else { return false }
        return !tokens.refreshToken.isEmpty
    }
    
    func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
