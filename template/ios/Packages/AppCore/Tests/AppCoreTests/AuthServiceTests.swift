import Foundation
import Testing

@testable import AppCore

@Suite("Authentication service")
struct AuthServiceTests {
    let stub = StubServer()

    func service(_ store: TokenStore) -> AuthService { stub.auth(store) }

    @Test("sign-in sends the credentials once, with no cookie and no Origin, and stores only the token")
    func signIn() async throws {
        stub.reset { request, body in
            Fixture.json(request.url!, 200, #"{"token":"x","user":{}}"#, headers: [AuthService.tokenHeader: Fixture.token])
        }
        let store = InMemoryTokenStore()
        try await service(store).signIn(email: "a@example.test", password: "a long local passphrase 42")
        #expect(try store.load() == Fixture.token)
        let request = try #require(stub.seen.first)
        #expect(request.url?.path == "/api/auth/sign-in/email" && request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Origin") == nil && request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(stub.seen.count == 1)
    }

    @Test("the password is in the request body only")
    func passwordOnlyInBody() async throws {
        let seenBody = Box<String>()
        stub.reset { request, body in
            seenBody.value = String(decoding: body, as: UTF8.self)
            return Fixture.json(request.url!, 200, "{}", headers: [AuthService.tokenHeader: Fixture.token])
        }
        try await service(InMemoryTokenStore()).signIn(email: "a@example.test", password: "a long local passphrase 42")
        #expect(seenBody.value?.contains("a long local passphrase 42") == true)
        let request = try #require(stub.seen.first)
        #expect(!(request.url?.absoluteString.contains("passphrase") ?? false))
        #expect(request.allHTTPHeaderFields?.values.contains { $0.contains("passphrase") } != true)
    }

    @Test("sign-up posts the name and stores the token")
    func signUp() async throws {
        let seenBody = Box<String>()
        stub.reset { request, body in
            seenBody.value = String(decoding: body, as: UTF8.self)
            return Fixture.json(request.url!, 200, "{}", headers: [AuthService.tokenHeader: Fixture.token])
        }
        let store = InMemoryTokenStore()
        try await service(store).signUp(email: "a@example.test", password: "a long local passphrase 42", name: "Ann")
        #expect(stub.seen.first?.url?.path == "/api/auth/sign-up/email" && seenBody.value?.contains("\"name\":\"Ann\"") == true)
        #expect(try store.load() == Fixture.token)
    }

    @Test("a 200 without a token, or with an implausible one, stores nothing")
    func missingToken() async throws {
        for headers in [[:], [AuthService.tokenHeader: "short"], [AuthService.tokenHeader: "has space inside the token value"]] as [[String: String]] {
            stub.reset { request, _ in Fixture.json(request.url!, 200, "{}", headers: headers) }
            let store = InMemoryTokenStore()
            await #expect(throws: AppError.self) { try await service(store).signIn(email: "a@example.test", password: "p") }
            #expect(try store.load() == nil)
        }
    }

    @Test("wrong credentials, rate limits and rejected sign-ups are told apart")
    func failures() async throws {
        let store = InMemoryTokenStore()
        stub.reset { r, _ in Fixture.json(r.url!, 401, #"{"code":"INVALID_EMAIL_OR_PASSWORD","message":"Invalid email or password"}"#) }
        await #expect(throws: AppError.invalidCredentials) { try await service(store).signIn(email: "a@example.test", password: "x") }
        stub.reset { r, _ in Fixture.json(r.url!, 429, #"{"message":"Too many requests"}"#) }
        await #expect(throws: AppError.rateLimited) { try await service(store).signIn(email: "a@example.test", password: "x") }
        stub.reset { r, _ in Fixture.json(r.url!, 422, #"{"code":"USER_ALREADY_EXISTS","message":"User already exists"}"#) }
        do {
            try await service(store).signUp(email: "a@example.test", password: "x", name: "A")
            Issue.record("expected a failure")
        } catch AppError.problem(let problem) {
            #expect(problem.status == 422 && problem.code == "user_already_exists" && problem.title == "User already exists")
        }
        stub.reset { r, _ in Fixture.json(r.url!, 503, "") }
        await #expect(throws: AppError.unexpectedStatus(503)) { try await service(store).signIn(email: "a@example.test", password: "x") }
        #expect(try store.load() == nil)
    }

    @Test("an unreachable server is a network error, and nothing is stored")
    func offline() async throws {
        stub.reset { _, _ in throw URLError(.notConnectedToInternet) }
        let store = InMemoryTokenStore()
        await #expect(throws: AppError.network("\(URLError.notConnectedToInternet.rawValue)")) { try await service(store).signIn(email: "a@example.test", password: "x") }
        #expect(try store.load() == nil)
    }

    @Test("sign-out asks the server with the bearer token, then removes the token")
    func signOut() async throws {
        stub.reset { r, _ in Fixture.json(r.url!, 200, #"{"success":true}"#) }
        let store = InMemoryTokenStore(token: Fixture.token)
        #expect(try await service(store).signOut() == .revoked)
        let request = try #require(stub.seen.first)
        #expect(request.url?.path == "/api/auth/sign-out" && request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Fixture.token)")
        #expect(try store.load() == nil)
    }

    @Test("a session the server already ended counts as revoked")
    func alreadyEnded() async throws {
        stub.reset { r, _ in Fixture.json(r.url!, 401, "{}") }
        let store = InMemoryTokenStore(token: Fixture.token)
        #expect(try await service(store).signOut() == .revoked)
        #expect(try store.load() == nil)
    }

    @Test("when the server cannot be told, the local token is still removed and the outcome says so")
    func unreachable() async throws {
        stub.reset { _, _ in throw URLError(.timedOut) }
        let store = InMemoryTokenStore(token: Fixture.token)
        let outcome = try await service(store).signOut()
        guard case .notRevoked(.network) = outcome else { Issue.record("expected notRevoked, got \(outcome)"); return }
        #expect(try store.load() == nil)
    }

    @Test("signing out with nothing stored makes no request")
    func nothingStored() async throws {
        stub.reset { r, _ in Fixture.json(r.url!, 200, "{}") }
        #expect(try await service(InMemoryTokenStore()).signOut() == .revoked)
        #expect(stub.seen.isEmpty)
    }
}

final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value?
    var value: Value? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
