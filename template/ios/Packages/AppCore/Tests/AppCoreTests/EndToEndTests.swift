import Foundation
import Testing

@testable import AppCore

// The same scenario as the real end-to-end test (AppTests/EndToEndTests.swift, run against a real server by
// ios/scripts/e2e.mjs), but against an in-process stand-in for the server, so it runs anywhere, every time.
@MainActor
@Suite("Whole scenario against a stand-in server")
struct ScenarioTests {
    let stub = StubServer()

    @Test("sign in, create, read, update, a second account is refused, delete, sign out, the old token is refused")
    func scenario() async throws {
        let live = Box<Set<String>>()
        live.value = []
        let items = Box<[String: (owner: String, title: String)]>()
        items.value = [:]
        let id = "33333333-3333-4333-8333-333333333333"
        let tokens = ["alice": Fixture.token, "bob": "Ym9iLXRva2VuLXZhbHVlLWJvYg.c2lnbmF0dXJlLWJvYg"]

        stub.reset { request, body in
            let url = request.url!
            let path = url.path
            let text = String(decoding: body, as: UTF8.self)
            func who() -> String? {
                guard let header = request.value(forHTTPHeaderField: "Authorization"), header.hasPrefix("Bearer ") else { return nil }
                let token = String(header.dropFirst(7))
                return tokens.first { $0.value == token && (live.value ?? []).contains(token) }?.key
            }
            switch (request.httpMethod!, path) {
            case ("POST", "/api/auth/sign-in/email"):
                let name = text.contains("alice@") ? "alice" : "bob"
                live.value = (live.value ?? []).union([tokens[name]!])
                return Fixture.json(url, 200, "{}", headers: [AuthService.tokenHeader: tokens[name]!])
            case ("POST", "/api/auth/sign-out"):
                if let user = who() { live.value?.remove(tokens[user]!) }
                return Fixture.json(url, 200, #"{"success":true}"#)
            default: break
            }
            guard let user = who() else { return Fixture.problem(url, 401, code: "unauthenticated") }
            switch (request.httpMethod!, path) {
            case ("GET", "/api/v1/session"):
                return Fixture.json(url, 200, #"{"user":{"id":"\#(user)","email":"\#(user)@example.test","name":"\#(user)"},"session":{"expiresAt":"2030-01-02T03:04:05.000Z"}}"#)
            case ("POST", "/api/v1/items"):
                items.value?[id] = (user, text.contains("Updated") ? "Updated" : "First")
                return Fixture.json(url, 201, Fixture.item(id, title: "First"))
            case ("GET", "/api/v1/items"):
                let mine = (items.value ?? [:]).filter { $0.value.owner == user }.map { Fixture.item($0.key, title: $0.value.title) }
                return Fixture.json(url, 200, "{\"items\":[\(mine.joined(separator: ","))],\"limit\":20,\"offset\":0}")
            default:
                guard path == "/api/v1/items/\(id)" else { return Fixture.problem(url, 404, code: "not_found") }
                guard let row = items.value?[id], row.owner == user else { return Fixture.problem(url, 404, code: "not_found") }
                switch request.httpMethod! {
                case "GET": return Fixture.json(url, 200, Fixture.item(id, title: row.title))
                case "PATCH":
                    items.value?[id] = (user, "Updated")
                    return Fixture.json(url, 200, Fixture.item(id, title: "Updated"))
                default:
                    items.value?[id] = nil
                    return (Fixture.response(url, 204), Data())
                }
            }
        }

        func model(_ store: TokenStore) -> AppModel {
            AppModel(environment: AppEnvironment(configuration: stub.configuration, tokenStore: store, session: stub.session))
        }
        let aliceStore = InMemoryTokenStore()
        let alice = model(aliceStore)
        await alice.restore()
        #expect(alice.state == .signedOut(.none))
        await alice.signIn(email: "alice@example.test", password: "a long local passphrase 42")
        #expect(alice.state.session?.user.email == "alice@example.test")
        #expect(try aliceStore.load() == Fixture.token)

        let api = alice.environment.api
        let created = try await api.createItem(title: "First", body: "")
        #expect(try await api.item(id: created.id).title == "First")
        #expect(try await api.updateItem(id: created.id, title: "Updated", body: nil).title == "Updated")

        let bob = model(InMemoryTokenStore())
        await bob.signIn(email: "bob@example.test", password: "a long local passphrase 42")
        for attempt in [
            { _ = try await bob.environment.api.item(id: created.id) },
            { _ = try await bob.environment.api.updateItem(id: created.id, title: "x", body: nil) },
            { try await bob.environment.api.deleteItem(id: created.id) },
        ] as [() async throws -> Void] {
            do {
                try await attempt()
                Issue.record("bob reached alice's item")
            } catch AppError.problem(let problem) { #expect(problem.status == 404) }
        }
        #expect(try await bob.environment.api.listItems().isEmpty)

        // a relaunch: a new model over the same store is still signed in
        let relaunched = model(aliceStore)
        await relaunched.restore()
        #expect(relaunched.state.session?.user.name == "alice")
        try await relaunched.environment.api.deleteItem(id: created.id)
        #expect(try await relaunched.environment.api.listItems().isEmpty)

        let oldToken = try #require(try aliceStore.load())
        await relaunched.signOut()
        #expect(relaunched.state == .signedOut(.none))
        #expect(try aliceStore.load() == nil)
        var request = URLRequest(url: stub.configuration.baseURL.appending(path: "/api/v1/session"))
        request.setValue("Bearer \(oldToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await stub.session.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 401 && ProblemDetails.decode(data)?.code == "unauthenticated")
    }
}
