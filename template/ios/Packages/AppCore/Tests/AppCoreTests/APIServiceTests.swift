import Foundation
import Testing

@testable import AppCore

@Suite("API service")
struct APIServiceTests {
    let stub = StubServer()
    let id = "11111111-1111-4111-8111-111111111111"

    func service(_ store: TokenStore = InMemoryTokenStore(token: Fixture.token), failures: FailureCounter = FailureCounter()) -> APIService {
        stub.service(store: store, failures: failures)
    }

    static func object(_ json: String?) throws -> [String: String] {
        try #require(JSONSerialization.jsonObject(with: Data((json ?? "").utf8)) as? [String: String])
    }

    @Test("the session endpoint decodes the user and the expiry, and the request carries the bearer token")
    func session() async throws {
        stub.reset { r, _ in Fixture.json(r.url!, 200, #"{"user":{"id":"u1","email":"a@example.test","name":"Ann"},"session":{"expiresAt":"2030-01-02T03:04:05.000Z"}}"#) }
        let session = try await service().currentSession()
        #expect(session.user == AuthenticatedUser(id: "u1", email: "a@example.test", name: "Ann"))
        #expect(session.expiresAt == Date(timeIntervalSince1970: 1_893_553_445))
        let request = try #require(stub.seen.first)
        #expect(request.url?.path == "/api/v1/session" && request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Fixture.token)")
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil && request.value(forHTTPHeaderField: "Origin") == nil)
    }

    @Test("listing sends limit and offset and decodes items; fields it does not know are ignored")
    func list() async throws {
        stub.reset { r, _ in
            Fixture.json(r.url!, 200, "{\"items\":[\(Fixture.item().replacingOccurrences(of: "}", with: ",\"future\":42}"))],\"limit\":5,\"offset\":10,\"newField\":true}")
        }
        let items = try await service().listItems(limit: 5, offset: 10)
        #expect(items.map(\.title) == ["Milk"] && items.first?.id == id)
        let query = try #require(stub.seen.first?.url?.query)
        #expect(query.contains("limit=5") && query.contains("offset=10"))
    }

    @Test("create posts JSON and returns the created item")
    func create() async throws {
        let sent = Box<String>()
        stub.reset { r, body in
            sent.value = String(decoding: body, as: UTF8.self)
            return Fixture.json(r.url!, 201, Fixture.item(title: "Bread", body: ""), headers: ["Location": "/api/v1/items/\(self.id)"])
        }
        let item = try await service().createItem(title: "Bread", body: "")
        #expect(item.title == "Bread")
        let request = try #require(stub.seen.first)
        #expect(request.httpMethod == "POST" && request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/json") == true)
        #expect(try Self.object(sent.value) == ["title": "Bread", "body": ""])
    }

    @Test("update sends only what changed; delete answers 204")
    func updateAndDelete() async throws {
        let sent = Box<String>()
        stub.reset { r, body in
            sent.value = String(decoding: body, as: UTF8.self)
            if r.httpMethod == "DELETE" { return (Fixture.response(r.url!, 204), Data()) }
            return Fixture.json(r.url!, 200, Fixture.item(title: "Oat milk"))
        }
        let item = try await service().updateItem(id: id, title: "Oat milk", body: nil)
        #expect(item.title == "Oat milk" && stub.seen.last?.httpMethod == "PATCH" && stub.seen.last?.url?.path == "/api/v1/items/\(id)")
        #expect(try Self.object(sent.value) == ["title": "Oat milk"])  // only what changed
        try await service().deleteItem(id: id)
        #expect(stub.seen.last?.httpMethod == "DELETE")
    }

    @Test("someone else's item is the same 404 as a missing one, and it is not an authentication failure")
    func crossUser() async throws {
        let failures = FailureCounter()
        stub.reset { r, _ in Fixture.problem(r.url!, 404, code: "not_found", title: "No such API resource") }
        let store = InMemoryTokenStore(token: Fixture.token)
        for operation in [
            { try await self.service(store, failures: failures).item(id: self.id) as Any },
            { try await self.service(store, failures: failures).updateItem(id: self.id, title: "x", body: nil) as Any },
            { try await self.service(store, failures: failures).deleteItem(id: self.id) as Any },
        ] {
            do {
                _ = try await operation()
                Issue.record("expected not_found")
            } catch AppError.problem(let problem) {
                #expect(problem.status == 404 && problem.code == ProblemDetails.notFound)
            }
        }
        let reported = await failures.count
        #expect(try store.load() == Fixture.token && reported == 0)
    }

    @Test("validation problems carry their field errors")
    func validation() async throws {
        stub.reset { r, _ in Fixture.problem(r.url!, 422, code: "validation_failed", title: "The request is not valid", errors: #"[{"path":"title","message":"Title is required"}]"#) }
        do {
            _ = try await service().createItem(title: "", body: "")
            Issue.record("expected a validation problem")
        } catch let error as AppError {
            #expect(error.fieldErrors == ["title": "Title is required"])
        }
    }

    @Test("a 401 problem is an authentication failure: the token is removed and the app is told")
    func unauthenticated() async throws {
        let store = InMemoryTokenStore(token: Fixture.token)
        let failures = FailureCounter()
        stub.reset { r, _ in Fixture.problem(r.url!, 401, code: "unauthenticated", title: "Authentication is required") }
        await #expect(throws: AppError.unauthenticated) { try await self.service(store, failures: failures).listItems() }
        #expect(try store.load() == nil)
        #expect(await failures.count == 1)
    }

    @Test("an unknown problem code and an unknown status are surfaced, not hidden")
    func unknown() async throws {
        stub.reset { r, _ in Fixture.problem(r.url!, 500, code: "something_new", title: "New") }
        do {
            _ = try await service().listItems()
            Issue.record("expected a problem")
        } catch AppError.problem(let problem) { #expect(problem.code == "something_new") }
        stub.reset { r, _ in Fixture.json(r.url!, 418, "{}") }
        await #expect(throws: AppError.unexpectedStatus(418)) { try await self.service().listItems() }
    }

    @Test("malformed or unexpected answers are an invalid response, never a crash", arguments: [
        (200, "application/json", "not json at all"),
        (200, "application/json", "{\"items\":\"nope\",\"limit\":1,\"offset\":0}"),
        (200, "application/json", "{\"items\":[{\"id\":1}],\"limit\":1,\"offset\":0}"),
        (200, "application/json", ""),
        (200, "text/html", "<html>captive portal</html>"),
        (200, "application/xml", "<x/>"),
    ])
    func malformed(status: Int, contentType: String, body: String) async {
        stub.reset { r, _ in (Fixture.response(r.url!, status, headers: ["Content-Type": contentType]), Data(body.utf8)) }
        do {
            _ = try await service().listItems()
            Issue.record("expected an invalid response")
        } catch AppError.invalidResponse {
        } catch { Issue.record("expected invalidResponse, got \(error)") }
    }

    @Test("network failures are network errors", arguments: [URLError.notConnectedToInternet, .timedOut, .cannotFindHost, .networkConnectionLost, .serverCertificateUntrusted])
    func network(code: URLError.Code) async {
        stub.reset { _, _ in throw URLError(code) }
        do {
            _ = try await service().listItems()
            Issue.record("expected a network error")
        } catch AppError.network(let detail) { #expect(detail == "\(code.rawValue)") } catch { Issue.record("got \(error)") }
    }

    @Test("a redirect is never followed")
    func redirect() async {
        stub.reset { r, _ in (Fixture.response(r.url!, 302, headers: ["Location": "http://evil.example/steal"]), Data()) }
        do {
            _ = try await service().listItems()
            Issue.record("expected a failure")
        } catch is AppError {} catch { Issue.record("got \(error)") }
        #expect(stub.seen.allSatisfy { $0.url?.host == "localhost" })
    }
}
