import Foundation
import Testing

@testable import AppCore

/// The real scenario against a real server, database and Better Auth, driven by `ios/scripts/e2e.mjs`:
///
///   phase one: sign in, store the token in the Keychain, read the session, create / read / update an item,
///              prove a second account cannot touch it, leave the first account signed in.
///   (the script restarts the web server and the database)
///   phase two: a fresh app model finds the stored token and is still signed in, sees the item, deletes it,
///              signs out, and the old token is refused with 401.
///
/// Without the script's environment the suite is disabled, and the script fails if it did not run.
private let environment = ProcessInfo.processInfo.environment
private let phase = environment["E2E_PHASE"]

private func required(_ name: String) throws -> String { try #require(environment[name], "missing \(name)") }

@MainActor
private func makeModel(service: String) throws -> (AppModel, KeychainTokenStore) {
    let port = try required("E2E_PORT")
    let configuration = try APIConfiguration(scheme: "http", host: "127.0.0.1:\(port)", allowsInsecureLocalHTTP: true)
    let store = KeychainTokenStore(service: service)
    return (AppModel(environment: AppEnvironment(configuration: configuration, tokenStore: store)), store)
}

@MainActor
@Suite("End to end (real server)", .serialized)
struct EndToEndTests {
    static let service = "e2e.scenario.primary"

    @Test("phase one: sign in, CRUD, a second account is refused", .enabled(if: phase == "one"))
    func phaseOne() async throws {
        let (model, store) = try makeModel(service: Self.service)
        try store.clear()
        await model.restore()
        #expect(model.state == .signedOut(.none), "a clean start has nothing stored")

        // 1-3. sign in; the token goes to the Keychain; the session is read
        let email = try required("E2E_EMAIL_A")
        await model.signIn(email: email, password: try required("E2E_PASSWORD"))
        #expect(model.lastError == nil, "sign-in failed: \(model.lastError?.message ?? "")")
        let session = try #require(model.state.session)
        #expect(session.user.email == email && session.expiresAt > Date())
        let token = try #require(try store.load())
        #expect(token.contains("."), "the stored token is the signed one")
        #expect(try await model.environment.api.currentSession().user.email == email)

        // 4-6. create, read, update
        let api = model.environment.api
        let created = try await api.createItem(title: "E2E item", body: "from the simulator")
        #expect(try await api.item(id: created.id) == created)
        let updated = try await api.updateItem(id: created.id, title: "E2E item (edited)", body: nil)
        #expect(updated.title == "E2E item (edited)" && updated.body == created.body)
        #expect(try await api.listItems().map(\.id) == [created.id])

        // 7. a second account cannot see, change or delete it
        let (other, otherStore) = try makeModel(service: Self.service + ".other")
        try otherStore.clear()
        defer { try? otherStore.clear() }
        await other.signIn(email: try required("E2E_EMAIL_B"), password: try required("E2E_PASSWORD"))
        #expect(other.lastError == nil, "second sign-in failed: \(other.lastError?.message ?? "")")
        let foreign = other.environment.api
        for attempt in [
            { _ = try await foreign.item(id: created.id) },
            { _ = try await foreign.updateItem(id: created.id, title: "mine now", body: nil) },
            { try await foreign.deleteItem(id: created.id) },
        ] as [() async throws -> Void] {
            do {
                try await attempt()
                Issue.record("the second account reached the first account's item")
            } catch AppError.problem(let problem) {
                #expect(problem.status == 404 && problem.code == ProblemDetails.notFound)
            }
        }
        #expect(try await foreign.listItems().isEmpty)
        #expect(try await api.item(id: created.id).title == "E2E item (edited)", "the item is untouched")
        // The first account stays signed in: its token is in the Keychain for phase two.
    }

    @Test("phase two: relaunch, still signed in, delete, sign out, the old token is refused", .enabled(if: phase == "two"))
    func phaseTwo() async throws {
        // 12. a new model = a new launch of the app, after the server and the database restarted
        let (model, store) = try makeModel(service: Self.service)
        let oldToken = try #require(try store.load(), "phase one left a token in the Keychain")
        await model.restore()
        let session = try #require(model.state.session, "still signed in after the restart; got \(model.state)")
        #expect(session.user.email == (try required("E2E_EMAIL_A")))
        let api = model.environment.api
        let items = try await api.listItems()
        #expect(items.map(\.title) == ["E2E item (edited)"])

        // 9. delete
        try await api.deleteItem(id: try #require(items.first).id)
        #expect(try await api.listItems().isEmpty)

        // 10. sign out: the server ends the session, the Keychain is emptied, the app is signed out
        await model.signOut()
        #expect(model.state == .signedOut(.none))
        #expect(try store.load() == nil)

        // 11. the old token is dead on the server
        let base = model.environment.configuration.baseURL
        for path in ["/api/v1/session", "/api/v1/items", "/api/v1/sessions"] {
            var request = URLRequest(url: base.appending(path: path))
            request.setValue("Bearer \(oldToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await Networking.makeSession().data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 401, "\(path) with the old token")
            #expect(ProblemDetails.decode(data)?.code == ProblemDetails.unauthenticated)
        }
    }

    @Test("the scenario's own marker: the script requires this to run", .enabled(if: phase != nil))
    func marker() throws {
        FileHandle.standardError.write(Data("E2E-PHASE-RAN \(phase ?? "")\n".utf8))
    }
}
