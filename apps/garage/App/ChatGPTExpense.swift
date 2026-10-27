import CryptoKit
import Foundation
import Network
import SafariServices
import Security
import SwiftUI

private enum ChatGPTError: LocalizedError {
    case invalidCallback, invalidToken, permissionDenied, unavailable(String), invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidCallback: "No se pudo completar el inicio de sesión con ChatGPT."
        case .invalidToken: "No se pudo verificar la sesión de ChatGPT. Volvé a conectarla."
        case .permissionDenied: "La cuenta no autorizó usar su plan de ChatGPT en Garage."
        case .unavailable(let detail): detail
        case .invalidResponse: "OpenAI no devolvió un gasto válido. Probá otra vez."
        }
    }
}

private struct ChatGPTCredentials: Codable {
    var clientID: String
    var subject: String
    var email: String?
    var accessToken: String
    var refreshToken: String
    var idToken: String
    var expiresAt: Date
    var scopes: String
}

private enum ChatGPTKeychain {
    private static let service = "com.schoren.garage.chatgpt"

    static func read(_ key: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    static func write(_ data: Data, key: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess else { throw ChatGPTError.invalidToken }
    }

    static func delete(_ key: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword,
                       kSecAttrService as String: service,
                       kSecAttrAccount as String: key] as CFDictionary)
    }
}

private final class LoopbackCallback {
    private var listener: NWListener?
    private var continuation: CheckedContinuation<URL, Error>?
    private var completed = false
    var port: UInt16 { listener?.port?.rawValue ?? 0 }

    func start() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.receive(connection) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: .main)
        }
    }

    func callback() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in self.continuation = continuation }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        if !completed { continuation?.resume(throwing: CancellationError()) }
        continuation = nil
    }

    private func receive(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, _ in
            guard let self, !self.completed, let data else { connection.cancel(); return }
            let received = buffer + data
            guard received.count <= 8192 else { connection.cancel(); return }
            guard let request = String(data: received, encoding: .utf8) else { connection.cancel(); return }
            guard let range = request.range(of: "\r\n") else {
                self.receive(connection, buffer: received)
                return
            }
            let firstLine = String(request[..<range.lowerBound])
            let parts = firstLine.split(separator: " ")
            guard parts.count == 3, parts[0] == "GET",
                  let path = parts.dropFirst().first,
                  let url = URL(string: "http://127.0.0.1:\(self.port)\(path)"),
                  url.path == "/auth/callback" else {
                connection.cancel()
                return
            }
            self.completed = true
            let body = "<html><body><p>Garage ya recibió la autorización. Volvé a la app.</p></body></html>"
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in connection.cancel() })
            self.continuation?.resume(returning: url)
            self.continuation = nil
        }
    }
}

struct ChatGPTBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController { SFSafariViewController(url: url) }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

@MainActor final class ChatGPTExpense: ObservableObject {
    @Published private(set) var connected = false
    @Published private(set) var connecting = false
    @Published private(set) var email: String?
    @Published var browserURL: URL?
    @Published var message: String?

    private var credentials: ChatGPTCredentials?
    private var listener: LoopbackCallback?
    private let resource = "https://api.openai.com/v1"

    init() {
        if let data = ChatGPTKeychain.read("credentials"),
           let saved = try? JSONDecoder().decode(ChatGPTCredentials.self, from: data),
           saved.scopes.split(separator: " ").contains("chatgpt.tokens.use.direct") {
            credentials = saved
            connected = true
            email = saved.email
        }
    }

    func disconnect() async {
        if let credentials {
            do {
                var request = URLRequest(url: URL(string: "https://auth.openai.com/api/accounts/oauth/revoke")!)
                request.httpMethod = "POST"
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                request.httpBody = ["token": credentials.refreshToken,
                                    "token_type_hint": "refresh_token",
                                    "client_id": credentials.clientID]
                    .map { "\($0.key.formEncoded)=\($0.value.formEncoded)" }.joined(separator: "&").data(using: .utf8)
                let (_, response) = try await URLSession.shared.data(for: request)
                if (response as? HTTPURLResponse)?.statusCode != 200 {
                    message = "La sesión se quitó del iPhone. Revisá en ChatGPT si querés revocar el acceso remoto."
                }
            } catch {
                message = "La sesión se quitó del iPhone. Revisá en ChatGPT si querés revocar el acceso remoto."
            }
        }
        credentials = nil
        connected = false
        email = nil
        ChatGPTKeychain.delete("credentials")
    }

    func connect() async {
        guard !connecting else { return }
        connecting = true
        defer { connecting = false }
        do {
            let callback = LoopbackCallback()
            try await callback.start()
            listener = callback
            guard callback.port != 0 else { throw ChatGPTError.invalidCallback }
            let redirect = "http://127.0.0.1:\(callback.port)/auth/callback"
            let state = randomURLSafe(32)
            let nonce = randomURLSafe(32)
            let verifier = randomURLSafe(32)
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
            let hostID: String
            if let data = ChatGPTKeychain.read("hostID"), let saved = String(data: data, encoding: .utf8) { hostID = saved }
            else {
                hostID = "urn:uuid:\(UUID().uuidString.lowercased())"
                try ChatGPTKeychain.write(Data(hostID.utf8), key: "hostID")
            }
            var components = URLComponents(string: "https://auth.openai.com/api/accounts/authorize")!
            var query = [URLQueryItem(name: "client_id", value: credentials?.clientID ?? "dynamic_agent_client"),
                         URLQueryItem(name: "response_type", value: "code"),
                         URLQueryItem(name: "redirect_uri", value: redirect),
                         URLQueryItem(name: "scope", value: "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"),
                         URLQueryItem(name: "resource", value: resource),
                         URLQueryItem(name: "state", value: state),
                         URLQueryItem(name: "nonce", value: nonce),
                         URLQueryItem(name: "code_challenge_method", value: "S256"),
                         URLQueryItem(name: "code_challenge", value: challenge),
                         URLQueryItem(name: "ext_agent_host_id", value: hostID)]
            if credentials == nil { query.append(URLQueryItem(name: "agent_name_hint", value: "Garage")) }
            else if let idToken = credentials?.idToken { query.append(URLQueryItem(name: "id_token_hint", value: idToken)) }
            components.queryItems = query
            browserURL = components.url
            let returned = try await callback.callback()
            browserURL = nil
            callback.stop()
            listener = nil
            guard let returnedItems = URLComponents(url: returned, resolvingAgainstBaseURL: false)?.queryItems,
                  returnedItems.first(where: { $0.name == "state" })?.value == state,
                  returnedItems.first(where: { $0.name == "error" }) == nil,
                  let code = returnedItems.first(where: { $0.name == "code" })?.value else { throw ChatGPTError.invalidCallback }
            let issuedID = returnedItems.first(where: { $0.name == "client_id" })?.value ?? credentials?.clientID
            guard let issuedID, issuedID != "dynamic_agent_client",
                  credentials == nil || credentials?.clientID == issuedID else { throw ChatGPTError.invalidCallback }
            let response = try await tokenRequest(["grant_type": "authorization_code", "client_id": issuedID,
                                                   "code": code, "code_verifier": verifier,
                                                   "redirect_uri": redirect, "resource": resource])
            let identity = try await validateIDToken(response.idToken, clientID: issuedID, nonce: nonce)
            if let previous = credentials, previous.subject != identity.subject { throw ChatGPTError.invalidToken }
            guard response.scope.split(separator: " ").contains("chatgpt.tokens.use.direct") else { throw ChatGPTError.permissionDenied }
            let saved = ChatGPTCredentials(clientID: issuedID, subject: identity.subject, email: identity.email,
                                           accessToken: response.accessToken, refreshToken: response.refreshToken,
                                           idToken: response.idToken, expiresAt: Date().addingTimeInterval(response.expiresIn),
                                           scopes: response.scope)
            try save(saved)
            message = nil
        } catch {
            browserURL = nil
            listener?.stop()
            listener = nil
            if !(error is CancellationError) { message = error.localizedDescription }
        }
    }

    func cancelConnect() {
        browserURL = nil
        listener?.stop()
        listener = nil
    }

    func interpret(_ transcript: String) async throws -> ExpenseInterpretation {
        let token = try await accessToken()
        var catalog = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        catalog.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (catalogData, catalogResponse) = try await URLSession.shared.data(for: catalog)
        guard (catalogResponse as? HTTPURLResponse)?.statusCode == 200,
              let modelList = try? JSONDecoder().decode(ModelCatalog.self, from: catalogData),
              let model = modelList.models.first(where: { $0.slug == "gpt-6.1-sol" && $0.visibility == "list" })?.slug
                ?? modelList.models.first(where: { $0.visibility == "list" })?.slug else {
            throw ChatGPTError.unavailable("No hay modelos disponibles para esta cuenta de ChatGPT.")
        }
        let categories = FamilyBudget.categories.joined(separator: ", ")
        let definitions = """
        Hipoteca: cuota del crédito de vivienda. Servicios: luz, gas, agua, internet y teléfono del hogar. Impuestos: tributos y tasas. Prepaga: cobertura médica, consultas, farmacia y medicamentos. Super: alimentos, ingredientes y productos para abastecer el hogar. Salidas: comida preparada, restaurantes, bares, ocio y actividades recreativas. Auto: combustible, mantenimiento, peajes y automóvil. Moto - Seguro ATM: seguro de la moto. Seguro de vida - Zurich: póliza de vida. Colegio: cuotas y gastos escolares. Suscripciones: plataformas y servicios de pago periódico. Delia - Empleada doméstica: remuneración de Delia. Adelanto Hipoteca (Extraordinario SAC): pago extraordinario adelantado del crédito. Vacaciones: transporte, alojamiento y gastos de viaje. Reserva / Contingencias: ahorro de emergencia e imprevistos. Devoluciones Familiares: reintegros y préstamos entre familiares. Bolucompras: compras personales discrecionales. Bolucompras Misha: compras personales de Misha.
        """
        let today = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let instructions = """
        Extraé un gasto familiar argentino dicho en voz alta. Hoy es \(today). Inferí la categoría por el significado del gasto, con estas definiciones del presupuesto: \(definitions)
        Las únicas categorías válidas son \(categories). Pagadores posibles: \(FamilyBudget.payers.joined(separator: ", ")). No inventes pagador ni fecha. «Mil» y «lucas» indican miles de pesos. Respondé solamente un objeto JSON con amount (número en pesos o null), category (nombre exacto o null si es ambiguo), paidBy (nombre exacto o null si no se mencionó), detail (descripción breve) y date (AAAA-MM-DD o null). No agregues texto fuera del JSON.
        """
        let body: [String: Any] = ["model": model, "instructions": instructions,
                                   "input": [["role": "user", "content": transcript]],
                                   "store": false, "stream": true]
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ChatGPTError.unavailable("OpenAI no pudo interpretar el gasto con esta cuenta.")
        }
        var output = ""
        var completed = false
        for try await line in bytes.lines where line.hasPrefix("data: ") {
            guard let event = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(6).utf8)) as? [String: Any],
                  let type = event["type"] as? String else { continue }
            if type == "response.output_text.delta" { output += event["delta"] as? String ?? "" }
            if type == "response.failed" {
                let info = (event["response"] as? [String: Any])?["error"] as? [String: Any]
                throw ChatGPTError.unavailable(info?["message"] as? String ?? "OpenAI no pudo procesar el gasto.")
            }
            if type == "response.completed" { completed = true }
        }
        guard completed, let start = output.firstIndex(of: "{"), let end = output.lastIndex(of: "}"),
              let result = try? JSONDecoder().decode(ExpenseInterpretation.self, from: Data(output[start...end].utf8)),
              result.category == nil || FamilyBudget.categories.contains(result.category!) else { throw ChatGPTError.invalidResponse }
        return result
    }

    private func accessToken() async throws -> String {
        guard var saved = credentials else { throw ChatGPTError.unavailable("Conectá tu cuenta de ChatGPT para interpretar gastos.") }
        if saved.expiresAt > Date().addingTimeInterval(120) { return saved.accessToken }
        let response = try await tokenRequest(["grant_type": "refresh_token", "client_id": saved.clientID,
                                               "refresh_token": saved.refreshToken, "resource": resource])
        guard response.scope.split(separator: " ").contains("chatgpt.tokens.use.direct") else { throw ChatGPTError.permissionDenied }
        saved.accessToken = response.accessToken
        saved.refreshToken = response.refreshToken
        saved.expiresAt = Date().addingTimeInterval(response.expiresIn)
        saved.scopes = response.scope
        try save(saved)
        return saved.accessToken
    }

    private func save(_ value: ChatGPTCredentials) throws {
        try ChatGPTKeychain.write(JSONEncoder().encode(value), key: "credentials")
        credentials = value
        connected = true
        email = value.email
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let idToken: String
        let expiresIn: TimeInterval
        let scope: String
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token", refreshToken = "refresh_token", idToken = "id_token"
            case expiresIn = "expires_in", scope
        }
    }

    private func tokenRequest(_ parameters: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://auth.openai.com/api/accounts/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = parameters.map { "\($0.key.formEncoded)=\($0.value.formEncoded)" }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ChatGPTError.invalidToken }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private struct Identity { let subject: String; let email: String? }
    private func validateIDToken(_ token: String, clientID: String, nonce: String) async throws -> Identity {
        let parts = token.split(separator: ".")
        guard parts.count == 3,
              let headerData = Data(base64URL: String(parts[0])),
              let payloadData = Data(base64URL: String(parts[1])),
              let signature = Data(base64URL: String(parts[2])),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              header["alg"] as? String == "RS256", let kid = header["kid"] as? String else { throw ChatGPTError.invalidToken }
        let (keysData, response) = try await URLSession.shared.data(from: URL(string: "https://auth.openai.com/.well-known/jwks.json")!)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let jwks = try? JSONSerialization.jsonObject(with: keysData) as? [String: Any],
              let keys = jwks["keys"] as? [[String: Any]],
              let jwk = keys.first(where: { $0["kid"] as? String == kid && $0["kty"] as? String == "RSA" }),
              let n = Data(base64URL: jwk["n"] as? String ?? ""),
              let e = Data(base64URL: jwk["e"] as? String ?? ""),
              let publicKey = Self.rsaKey(modulus: n, exponent: e),
              SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256,
                                    Data("\(parts[0]).\(parts[1])".utf8) as CFData, signature as CFData, nil),
              payload["iss"] as? String == "https://auth.openai.com",
              payload["aud"] as? String == clientID,
              (payload["exp"] as? TimeInterval ?? 0) > Date().timeIntervalSince1970,
              payload["nonce"] as? String == nonce,
              let subject = payload["sub"] as? String else { throw ChatGPTError.invalidToken }
        return Identity(subject: subject, email: payload["email"] as? String)
    }

    private static func rsaKey(modulus: Data, exponent: Data) -> SecKey? {
        func length(_ count: Int) -> Data {
            if count < 128 { return Data([UInt8(count)]) }
            let bytes = withUnsafeBytes(of: UInt32(count).bigEndian) { Data($0) }.drop { $0 == 0 }
            return Data([0x80 | UInt8(bytes.count)]) + bytes
        }
        func integer(_ value: Data) -> Data {
            let unsigned = value.first.map { $0 & 0x80 != 0 } == true ? Data([0]) + value : value
            return Data([0x02]) + length(unsigned.count) + unsigned
        }
        let sequence = integer(modulus) + integer(exponent)
        let der = Data([0x30]) + length(sequence.count) + sequence
        return SecKeyCreateWithData(der as CFData, [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                                     kSecAttrKeyClass as String: kSecAttrKeyClassPublic] as CFDictionary, nil)
    }

    private struct ModelCatalog: Decodable {
        struct Model: Decodable { let slug: String; let visibility: String? }
        let models: [Model]
    }

    private func randomURLSafe(_ count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64URLEncoded()
    }
}

private extension Data {
    init?(base64URL: String) {
        let padded = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        self.init(base64Encoded: padded + String(repeating: "=", count: (4 - padded.count % 4) % 4))
    }
    func base64URLEncoded() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

private extension String {
    var formEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? self
    }
}
