import Foundation
import Testing

@testable import AppCore

@MainActor
@Suite("App and items models")
struct ModelTests {
    let stub = StubServer()
    let sessionJSON = #"{"user":{"id":"u1","email":"a@example.test","name":"Ann"},"session":{"expiresAt":"2030-01-02T03:04:05.000Z"}}"#

    func model(_ store: TokenStore) -> AppModel {
        AppModel(environment: AppEnvironment(configuration: stub.configuration, tokenStore: store, session: stub.session))
    }

    @Test("launching with no stored token is signed out and asks nothing of the server")
    func nothingStored() async {
        stub.reset { r, _ in Fixture.json(r.url!, 200, "{}") }
        let model = model(InMemoryTokenStore())
        await model.restore()
        #expect(model.state == .signedOut(.none) && stub.seen.isEmpty)
    }

    @Test("launching with a stored token the server accepts is signed in")
    func accepted() async {
        stub.reset { r, _ in Fixture.json(r.url!, 200, self.sessionJSON) }
        let model = model(InMemoryTokenStore(token: Fixture.token))
        await model.restore()
        #expect(model.state.session?.user.email == "a@example.test")
    }

    @Test("launching with a token the server rejects clears it and says the session ended")
    func rejected() async throws {
        stub.reset { r, _ in Fixture.problem(r.url!, 401, code: "unauthenticated") }
        let store = InMemoryTokenStore(token: Fixture.token)
        let model = model(store)
        await model.restore()
        #expect(model.state == .signedOut(.sessionEnded))
        #expect(try store.load() == nil)
    }

    @Test("launching offline keeps the token and does not sign the person out")
    func offline() async throws {
        stub.reset { _, _ in throw URLError(.notConnectedToInternet) }
        let store = InMemoryTokenStore(token: Fixture.token)
        let model = model(store)
        await model.restore()
        guard case .unconfirmed(.network) = model.state else { Issue.record("got \(model.state)"); return }
        #expect(try store.load() == Fixture.token)
    }

    @Test("sign-in stores the token, loads the session and signs in; sign-out ends it and returns to signed-out")
    func signInOut() async throws {
        stub.reset { r, _ in
            switch r.url!.path {
            case "/api/auth/sign-in/email": return Fixture.json(r.url!, 200, "{}", headers: [AuthService.tokenHeader: Fixture.token])
            case "/api/auth/sign-out": return Fixture.json(r.url!, 200, #"{"success":true}"#)
            default: return Fixture.json(r.url!, 200, self.sessionJSON)
            }
        }
        let store = InMemoryTokenStore()
        let model = model(store)
        await model.signIn(email: "a@example.test", password: "a long local passphrase 42")
        #expect(model.state.session?.user.name == "Ann" && model.lastError == nil)
        #expect(try store.load() == Fixture.token)
        await model.signOut()
        #expect(model.state == .signedOut(.none))
        #expect(try store.load() == nil)
        #expect(stub.seen.map(\.url?.path) == ["/api/auth/sign-in/email", "/api/v1/session", "/api/auth/sign-out"])
    }

    @Test("a failed sign-in keeps the app signed out and shows the error")
    func failedSignIn() async {
        stub.reset { r, _ in Fixture.json(r.url!, 401, #"{"code":"INVALID_EMAIL_OR_PASSWORD"}"#) }
        let model = model(InMemoryTokenStore())
        await model.restore()
        await model.signIn(email: "a@example.test", password: "wrong")
        #expect(model.state == .signedOut(.none) && model.lastError == .invalidCredentials)
    }

    @Test("a 401 in the middle of use signs the app out through the middleware")
    func sessionRevokedWhileSignedIn() async throws {
        let calls = Box<Int>()
        stub.reset { r, _ in
            calls.value = (calls.value ?? 0) + 1
            if r.url!.path == "/api/v1/session" && calls.value == 1 { return Fixture.json(r.url!, 200, self.sessionJSON) }
            return Fixture.problem(r.url!, 401, code: "unauthenticated")
        }
        let store = InMemoryTokenStore(token: Fixture.token)
        let model = model(store)
        await model.restore()
        #expect(model.state.session != nil)
        let items = ItemsModel(api: model.environment.api)
        await items.load()
        #expect(model.state == .signedOut(.sessionEnded))
        #expect(try store.load() == nil)
        guard case .failed(.unauthenticated) = items.phase else { Issue.record("got \(items.phase)"); return }
    }

    @Test("the items list: load, empty, create, edit, delete")
    func items() async {
        let state = Box<[String]>()
        state.value = []
        stub.reset { r, body in
            switch (r.httpMethod!, r.url!.path) {
            case ("GET", "/api/v1/items"):
                let rows = (state.value ?? []).map { Fixture.item($0, title: "Item \($0.prefix(1))") }.joined(separator: ",")
                return Fixture.json(r.url!, 200, "{\"items\":[\(rows)],\"limit\":100,\"offset\":0}")
            case ("POST", _):
                state.value = ["2222222-2222-4222-8222-222222222222".replacingOccurrences(of: "2222222-", with: "22222222-")] + (state.value ?? [])
                return Fixture.json(r.url!, 201, Fixture.item("22222222-2222-4222-8222-222222222222", title: "New one"))
            case ("PATCH", _): return Fixture.json(r.url!, 200, Fixture.item("22222222-2222-4222-8222-222222222222", title: "Renamed"))
            default:
                state.value = []
                return (Fixture.response(r.url!, 204), Data())
            }
        }
        let model = ItemsModel(api: stub.service(store: InMemoryTokenStore(token: Fixture.token)))
        #expect(model.phase == .idle && !model.isEmpty)
        await model.load()
        #expect(model.phase == .loaded && model.isEmpty)
        #expect(await model.create(title: "New one", body: "") && model.items.map(\.title) == ["New one"])
        let created = model.items[0]
        #expect(await model.update(created, title: "Renamed", body: "") && model.items.map(\.title) == ["Renamed"])
        await model.delete(created)
        #expect(model.items.isEmpty)
    }

    @Test("a validation error keeps the form open and reports the field; a network error on load is a failed phase")
    func itemErrors() async {
        stub.reset { r, _ in Fixture.problem(r.url!, 422, code: "validation_failed", title: "The request is not valid", errors: #"[{"path":"title","message":"Title is required"}]"#) }
        let model = ItemsModel(api: stub.service(store: InMemoryTokenStore(token: Fixture.token)))
        #expect(await model.create(title: "", body: "") == false)
        #expect(model.actionError?.fieldErrors == ["title": "Title is required"])
        model.dismissActionError()
        #expect(model.actionError == nil)
        stub.reset { _, _ in throw URLError(.notConnectedToInternet) }
        await model.load()
        guard case .failed(.network) = model.phase else { Issue.record("got \(model.phase)"); return }
    }
}
