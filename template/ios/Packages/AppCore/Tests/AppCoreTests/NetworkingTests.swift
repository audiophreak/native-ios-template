import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing

@testable import AppCore

@Suite("Session settings")
struct NetworkingTests {
    @Test("no cookies, no cache, bounded time, and the system's certificate validation")
    func settings() {
        let session = Networking.makeSession()
        let configuration = session.configuration
        #expect(configuration.httpShouldSetCookies == false && configuration.httpCookieStorage == nil && configuration.urlCache == nil)
        #expect(configuration.httpCookieAcceptPolicy == .never)
        #expect(configuration.timeoutIntervalForRequest <= 30 && configuration.timeoutIntervalForResource <= 60)
        // Nothing here replaces the delegate's authentication-challenge handling, so TLS validation is the system's.
        #expect(!(session.delegate is URLSessionDelegate && session.delegate?.responds(to: Selector(("URLSession:didReceiveChallenge:completionHandler:"))) == true))
    }
}

@Suite("Bearer middleware")
struct BearerMiddlewareTests {
    let stub = StubServer()
    var base: URL { stub.configuration.baseURL }

    private func run(
        store: TokenStore, baseURL: URL? = nil, status: Int = 200, headers: [HTTPField.Name: String] = [:],
        failures: FailureCounter = FailureCounter()
    ) async throws -> HTTPRequest {
        let middleware = BearerAuthMiddleware(apiBaseURL: base, tokenStore: store) { await failures.record() }
        let sent = Captured()
        var built = HTTPFields()
        for (name, value) in headers { built[name] = value }
        let fields = built
        _ = try await middleware.intercept(HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/api/v1/items"), body: nil, baseURL: baseURL ?? base, operationID: "listItems") { request, body, _ in
            await sent.set(request)
            return (HTTPResponse(status: .init(code: status), headerFields: fields), body)
        }
        return await sent.value!
    }

    @Test("it adds the bearer header when a token is stored")
    func adds() async throws {
        let request = try await run(store: InMemoryTokenStore(token: Fixture.token))
        #expect(request.headerFields[.authorization] == "Bearer \(Fixture.token)")
    }

    @Test("it adds nothing when there is no token")
    func none() async throws {
        #expect(try await run(store: InMemoryTokenStore()).headerFields[.authorization] == nil)
    }

    @Test("the token is never sent to another origin", arguments: ["https://localhost:3000", "http://localhost:3001", "http://evil.example:3000"])
    func otherOrigin(other: String) async throws {
        let request = try await run(store: InMemoryTokenStore(token: Fixture.token), baseURL: URL(string: other))
        #expect(request.headerFields[.authorization] == nil)
    }

    @Test("a 401 problem for a request that carried the token removes it and reports the failure")
    func confirmed401() async throws {
        let store = InMemoryTokenStore(token: Fixture.token)
        let failures = FailureCounter()
        _ = try await run(store: store, status: 401, headers: [.contentType: "application/problem+json; charset=utf-8"], failures: failures)
        #expect(try store.load() == nil)
        #expect(await failures.count == 1)
    }

    @Test("a 401 that is not the API's problem document (a proxy, say) does not end the session")
    func unconfirmed401() async throws {
        let store = InMemoryTokenStore(token: Fixture.token)
        let failures = FailureCounter()
        _ = try await run(store: store, status: 401, headers: [.contentType: "text/html"], failures: failures)
        let reported = await failures.count
        #expect(try store.load() == Fixture.token && reported == 0)
    }

    @Test("a 401 for a request that carried no token has nothing to clear and reports nothing")
    func noTokenNoReport() async throws {
        let failures = FailureCounter()
        _ = try await run(store: InMemoryTokenStore(), status: 401, headers: [.contentType: "application/problem+json"], failures: failures)
        #expect(await failures.count == 0)
    }

    @Test("other failures keep the token")
    func otherStatuses() async throws {
        for status in [403, 404, 422, 500] {
            let store = InMemoryTokenStore(token: Fixture.token)
            _ = try await run(store: store, status: status, headers: [.contentType: "application/problem+json"])
            #expect(try store.load() == Fixture.token, "status \(status)")
        }
    }

    @Test("a rotated token from the server replaces the stored one; an implausible one is ignored")
    func rotation() async throws {
        let store = InMemoryTokenStore(token: Fixture.token)
        let rotated = "cm90YXRlZC10b2tlbi12YWx1ZQ.cm90YXRlZC1zaWduYXR1cmU"
        _ = try await run(store: store, headers: [HTTPField.Name("set-auth-token")!: rotated])
        #expect(try store.load() == rotated)
        _ = try await run(store: store, headers: [HTTPField.Name("set-auth-token")!: "short"])
        #expect(try store.load() == rotated)
    }
}

actor Captured {
    private(set) var value: HTTPRequest?
    func set(_ request: HTTPRequest) { value = request }
}
