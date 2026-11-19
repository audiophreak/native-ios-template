import Foundation

public struct AuthenticatedUser: Equatable, Sendable {
    public var id: String
    public var email: String
    public var name: String
    public init(id: String, email: String, name: String) {
        self.id = id
        self.email = email
        self.name = name
    }
}

public struct SessionInfo: Equatable, Sendable {
    public var user: AuthenticatedUser
    public var expiresAt: Date
    public init(user: AuthenticatedUser, expiresAt: Date) {
        self.user = user
        self.expiresAt = expiresAt
    }
}

public enum SignOutOutcome: Equatable, Sendable {
    /// The server ended the session (or had already ended it).
    case revoked
    /// The server could not be asked: the local credential is gone, the session on the server stays valid until it
    /// expires. The person should know.
    case notRevoked(AppError)
}

/// Token acquisition and release. These are Better Auth's documented endpoints (`/api/auth/*`), not part of the
/// application's own OpenAPI contract (docs/native-client.md in the web project explains the boundary), so they
/// are called directly here, in one small, separately tested place.
///
/// The password is a parameter and nothing else: it is sent over the configured API connection and never
/// stored, logged or kept in a property. The token that comes back is stored in the Keychain and nowhere else.
public struct AuthService: Sendable {
    public static let tokenHeader = "set-auth-token"

    private let configuration: APIConfiguration
    private let session: URLSession
    private let tokenStore: TokenStore

    public init(configuration: APIConfiguration, session: URLSession, tokenStore: TokenStore) {
        self.configuration = configuration
        self.session = session
        self.tokenStore = tokenStore
    }

    private struct Credentials: Encodable {
        var email: String
        var password: String
        var name: String?
    }

    public func signIn(email: String, password: String) async throws {
        try await acquireToken(path: "/api/auth/sign-in/email", Credentials(email: email, password: password))
    }

    /// Account creation. A deployment may have it disabled (open registration is off by default in production).
    public func signUp(email: String, password: String, name: String) async throws {
        try await acquireToken(path: "/api/auth/sign-up/email", Credentials(email: email, password: password, name: name))
    }

    /// 1. asks the server to end the session, 2. removes the Keychain token, whatever the answer was.
    public func signOut() async throws -> SignOutOutcome {
        let token = try tokenStore.load()
        var outcome = SignOutOutcome.revoked
        if let token {
            do {
                let (_, response) = try await send(path: "/api/auth/sign-out", body: Data("{}".utf8), bearer: token)
                switch response.statusCode {
                case 200...299, 401: break  // ended now, or it had ended already
                default: outcome = .notRevoked(.unexpectedStatus(response.statusCode))
                }
            } catch let error as AppError {
                outcome = .notRevoked(error)
            }
        }
        try tokenStore.clear()
        return outcome
    }

    private func acquireToken(path: String, _ credentials: Credentials) async throws {
        let body = try JSONEncoder().encode(credentials)
        let (data, response) = try await send(path: path, body: body, bearer: nil)
        switch response.statusCode {
        case 200:
            guard let token = response.value(forHTTPHeaderField: Self.tokenHeader), Self.isPlausible(token) else {
                throw AppError.invalidResponse("the server did not return a session token")
            }
            try tokenStore.save(token)
        case 401: throw AppError.invalidCredentials
        case 429: throw AppError.rateLimited
        case 400...499: throw Self.problem(from: data, status: response.statusCode)
        default: throw AppError.unexpectedStatus(response.statusCode)
        }
    }

    /// A signed session token is `value.signature`, URL-safe characters only. Anything else is not stored.
    static func isPlausible(_ token: String) -> Bool {
        guard (20...4096).contains(token.utf8.count) else { return false }
        return token.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && scalar.value > 32 && scalar.value < 127
        }
    }

    /// Better Auth reports errors as `{ "code": "...", "message": "..." }`; shown as a problem, never raw.
    static func problem(from data: Data, status: Int) -> AppError {
        struct Reported: Decodable {
            var code: String?
            var message: String?
        }
        let reported = try? JSONDecoder().decode(Reported.self, from: data)
        let title = reported?.message.map { String($0.prefix(100)) } ?? "The request was not accepted"
        return .problem(ProblemDetails(type: "urn:problem-type:auth", title: title, status: status, code: reported?.code?.lowercased() ?? "rejected"))
    }

    private func send(path: String, body: Data, bearer: String?) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: configuration.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AppError.invalidResponse("not an HTTP response") }
            return (data, http)
        } catch let error as AppError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AppError.network((error as? URLError).map { "\($0.code.rawValue)" } ?? "failed")
        }
    }
}
