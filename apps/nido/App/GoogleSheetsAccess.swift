import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

@MainActor final class GoogleSheetsAccess: NSObject, ASWebAuthenticationPresentationContextProviding {
    private struct Token: Codable {
        var access: String
        var refresh: String
        var expiry: Date
    }

    private let clientID = Bundle.main.object(forInfoDictionaryKey: "NidoGoogleClientID") as? String ?? ""
    private let keychainAccount = "family-budget-google-oauth"
    private var token: Token?
    private var session: ASWebAuthenticationSession?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }

    func restore() async -> Bool {
        token = readToken()
        guard token != nil else { return false }
        do { _ = try await accessToken(); return true }
        catch { return false }
    }

    func signOut() {
        token = nil
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrAccount: keychainAccount] as CFDictionary)
    }

    func signIn() async throws {
        guard !clientID.isEmpty, !clientID.contains("REPLACE") else { throw SheetsError.missingOAuthConfiguration }
        let redirectScheme = clientID.split(separator: ".").reversed().joined(separator: ".")
        let redirect = "\(redirectScheme):/oauth2redirect"
        let verifier = Self.randomVerifier()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        let state = UUID().uuidString
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/spreadsheets"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        let callback = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let auth = ASWebAuthenticationSession(url: components.url!, callbackURLScheme: redirectScheme) { url, error in
                if let error { continuation.resume(throwing: error) }
                else if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: SheetsError.authorizationFailed) }
            }
            auth.presentationContextProvider = self
            auth.prefersEphemeralWebBrowserSession = false
            session = auth
            if !auth.start() { continuation.resume(throwing: SheetsError.authorizationFailed) }
        }
        let returned = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard returned.first(where: { $0.name == "state" })?.value == state,
              let code = returned.first(where: { $0.name == "code" })?.value else { throw SheetsError.authorizationFailed }
        let response = try await exchange(["client_id": clientID, "code": code, "code_verifier": verifier,
                                           "grant_type": "authorization_code", "redirect_uri": redirect])
        guard let refresh = response.refreshToken else { throw SheetsError.noRefreshToken }
        token = Token(access: response.accessToken, refresh: refresh, expiry: .now.addingTimeInterval(response.expiresIn - 60))
        saveToken()
    }

    func values(_ range: String) async throws -> [[String]] {
        let encoded = range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        var url = URLComponents(string: "https://sheets.googleapis.com/v4/spreadsheets/\(FamilyBudget.spreadsheetID)/values/\(encoded)")!
        url.queryItems = [URLQueryItem(name: "valueRenderOption", value: "UNFORMATTED_VALUE"),
                          URLQueryItem(name: "dateTimeRenderOption", value: "SERIAL_NUMBER")]
        let data = try await request(url.url!, method: "GET", body: nil)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SheetsError.invalidResponse }
        return (object["values"] as? [[Any]] ?? []).map { row in row.map { String(describing: $0) } }
    }

    func append(_ row: [String], to range: String) async throws {
        let encoded = range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        var url = URLComponents(string: "https://sheets.googleapis.com/v4/spreadsheets/\(FamilyBudget.spreadsheetID)/values/\(encoded):append")!
        url.queryItems = [URLQueryItem(name: "valueInputOption", value: "USER_ENTERED"),
                          URLQueryItem(name: "insertDataOption", value: "INSERT_ROWS")]
        let body = try JSONEncoder().encode(ValuesResponse(values: [row]))
        _ = try await request(url.url!, method: "POST", body: body)
    }

    func update(_ row: [String], in range: String) async throws {
        let encoded = range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        var url = URLComponents(string: "https://sheets.googleapis.com/v4/spreadsheets/\(FamilyBudget.spreadsheetID)/values/\(encoded)")!
        url.queryItems = [URLQueryItem(name: "valueInputOption", value: "USER_ENTERED")]
        let body = try JSONEncoder().encode(ValuesResponse(values: [row]))
        _ = try await request(url.url!, method: "PUT", body: body)
    }

    func clear(_ range: String) async throws {
        let encoded = range.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
        let url = URL(string: "https://sheets.googleapis.com/v4/spreadsheets/\(FamilyBudget.spreadsheetID)/values/\(encoded):clear")!
        _ = try await request(url, method: "POST", body: Data("{}".utf8))
    }

    private func request(_ url: URL, method: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw SheetsError.invalidResponse }
        if status == 401 { throw SheetsError.authorizationExpired }
        guard (200..<300).contains(status) else { throw SheetsError.http(status) }
        return data
    }

    private func accessToken() async throws -> String {
        guard var token else { throw SheetsError.authorizationExpired }
        if token.expiry > .now { return token.access }
        let response = try await exchange(["client_id": clientID, "refresh_token": token.refresh,
                                           "grant_type": "refresh_token"])
        token.access = response.accessToken
        token.expiry = .now.addingTimeInterval(response.expiresIn - 60)
        self.token = token
        saveToken()
        return token.access
    }

    private func exchange(_ parameters: [String: String]) async throws -> OAuthResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters.map { key, value in
            "\(key.formEncoded)=\(value.formEncoded)"
        }.sorted().joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw SheetsError.authorizationFailed }
        return try JSONDecoder().decode(OAuthResponse.self, from: data)
    }

    private func readToken() -> Token? {
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrAccount: keychainAccount,
                     kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne] as CFDictionary
        var item: CFTypeRef?
        guard SecItemCopyMatching(query, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Token.self, from: data)
    }

    private func saveToken() {
        guard let token, let data = try? JSONEncoder().encode(token) else { return }
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrAccount: keychainAccount] as CFDictionary)
        SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrAccount: keychainAccount,
                    kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly] as CFDictionary, nil)
    }

    private static func randomVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}

private struct ValuesResponse: Codable {
    var values: [[String]]?
}

private struct OAuthResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in"
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var formEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .init(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")) ?? self
    }
}

private enum SheetsError: LocalizedError {
    case missingOAuthConfiguration, authorizationFailed, noRefreshToken, authorizationExpired, invalidResponse, http(Int)
    var errorDescription: String? {
        switch self {
        case .missingOAuthConfiguration: return "Falta configurar el cliente OAuth de Google para Nido."
        case .authorizationFailed: return "No se pudo autorizar Google Sheets."
        case .noRefreshToken: return "Google no entregó acceso persistente. Volvé a iniciar sesión."
        case .authorizationExpired: return "La sesión de Google venció. Volvé a iniciar sesión."
        case .invalidResponse: return "La respuesta de Google Sheets no fue válida."
        case .http(let code): return "Google Sheets devolvió el error \(code)."
        }
    }
}
