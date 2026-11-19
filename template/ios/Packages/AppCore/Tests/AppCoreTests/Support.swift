import Foundation

@testable import AppCore

/// An in-process stand-in for the server: a URLProtocol that answers from a closure, found by the request's port,
/// so every test has its own and tests can run in parallel. No network and no sockets.
final class StubServer: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest, Data) throws -> (HTTPURLResponse, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var servers: [Int: StubServer] = [:]
    nonisolated(unsafe) private static var nextPort = 20000

    let port: Int
    let configuration: APIConfiguration
    private let state = NSLock()
    private var handler: Handler?
    private var recorded: [URLRequest] = []

    init() {
        let port = Self.lock.withLock { () -> Int in
            Self.nextPort += 1
            return Self.nextPort
        }
        self.port = port
        self.configuration = try! APIConfiguration(scheme: "http", host: "localhost:\(port)", allowsInsecureLocalHTTP: true)
        Self.lock.withLock { Self.servers[port] = self }
    }

    func reset(_ handler: @escaping Handler) {
        state.withLock {
            self.handler = handler
            recorded = []
        }
    }

    var seen: [URLRequest] { state.withLock { recorded } }

    var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }

    func service(store: TokenStore, failures: FailureCounter = FailureCounter()) -> APIService {
        APIService.live(configuration: configuration, session: session, tokenStore: store) { await failures.record() }
    }

    func auth(_ store: TokenStore) -> AuthService { AuthService(configuration: configuration, session: session, tokenStore: store) }

    fileprivate static func server(for request: URLRequest) -> StubServer? {
        guard let port = request.url?.port else { return nil }
        return lock.withLock { servers[port] }
    }

    fileprivate func answer(_ request: URLRequest, body: Data) throws -> (HTTPURLResponse, Data) {
        let current = state.withLock { () -> Handler? in
            recorded.append(request)
            return handler
        }
        guard let current else { throw URLError(.badServerResponse) }
        return try current(request, body)
    }
}

final class StubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate(); stream.close() }
            while true {  // a blocking read: `hasBytesAvailable` can be false before the stream has produced anything
                let count = stream.read(buffer, maxLength: 4096)
                if count <= 0 { break }
                body.append(buffer, count: count)
            }
        }
        do {
            guard let server = StubServer.server(for: request) else { throw URLError(.cannotConnectToHost) }
            let (response, data) = try server.answer(request, body: body)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

enum Fixture {
    static let token = "dGVzdC10b2tlbi12YWx1ZQ.c2lnbmF0dXJlLXZhbHVl"  // a made-up shape, not a credential

    static func response(_ url: URL, _ status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    static func json(_ url: URL, _ status: Int, _ body: String, headers: [String: String] = [:]) -> (HTTPURLResponse, Data) {
        (response(url, status, headers: ["Content-Type": "application/json; charset=utf-8"].merging(headers) { $1 }), Data(body.utf8))
    }

    static func problem(_ url: URL, _ status: Int, code: String, title: String = "Problem", errors: String = "") -> (HTTPURLResponse, Data) {
        let extra = errors.isEmpty ? "" : ",\"errors\":\(errors)"
        let body = "{\"type\":\"urn:problem-type:\(code)\",\"title\":\"\(title)\",\"status\":\(status),\"code\":\"\(code)\"\(extra)}"
        return (response(url, status, headers: ["Content-Type": "application/problem+json; charset=utf-8", "Cache-Control": "no-store"]), Data(body.utf8))
    }

    static func item(_ id: String = "11111111-1111-4111-8111-111111111111", title: String = "Milk", body: String = "2 litres") -> String {
        "{\"id\":\"\(id)\",\"title\":\"\(title)\",\"body\":\"\(body)\",\"createdAt\":\"2026-01-02T03:04:05.000Z\",\"updatedAt\":\"2026-01-02T03:04:05.000Z\"}"
    }

}

actor FailureCounter {
    private(set) var count = 0
    func record() { count += 1 }
}
