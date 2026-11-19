import APIClient
import Foundation
import Testing

@testable import AppCore

@Suite("API configuration")
struct ConfigurationTests {
    @Test("https is accepted anywhere, and the URL is just the origin")
    func https() throws {
        let configuration = try APIConfiguration(scheme: "https", host: "api.example.com", allowsInsecureLocalHTTP: false)
        #expect(configuration.baseURL.absoluteString == "https://api.example.com")
        let withPort = try APIConfiguration(scheme: "HTTPS", host: "api.example.com:8443", allowsInsecureLocalHTTP: false)
        #expect(withPort.baseURL.absoluteString == "https://api.example.com:8443")
    }

    @Test("cleartext is only for a local address in a Debug build", arguments: ["localhost:3000", "127.0.0.1:3000", "mac.local:3000"])
    func localHTTP(host: String) throws {
        #expect(try APIConfiguration(scheme: "http", host: host, allowsInsecureLocalHTTP: true).baseURL.scheme == "http")
        #expect(throws: ConfigurationError.self) { try APIConfiguration(scheme: "http", host: host, allowsInsecureLocalHTTP: false) }
    }

    @Test("cleartext to a public host is refused even in Debug", arguments: ["api.example.com", "192.0.2.10:3000", "example.org"])
    func publicHTTP(host: String) {
        #expect(throws: ConfigurationError.self) { try APIConfiguration(scheme: "http", host: host, allowsInsecureLocalHTTP: true) }
    }

    @Test("credentials, paths, queries, fragments and other schemes are refused", arguments: [
        ("https", "user:secret@api.example.com"), ("https", "api.example.com/v1"), ("https", "api.example.com?x=1"),
        ("https", "api.example.com#frag"), ("ftp", "api.example.com"), ("https", ""), ("", "api.example.com"), ("https", "a b.example.com"),
    ])
    func refused(scheme: String, host: String) {
        #expect(throws: ConfigurationError.self) { try APIConfiguration(scheme: scheme, host: host, allowsInsecureLocalHTTP: true) }
    }

    @Test("it reads the two Info.plist keys and reports a missing one")
    func infoDictionary() throws {
        let configuration = try APIConfiguration(infoDictionary: ["APIScheme": "https", "APIHost": "api.example.com"], allowsInsecureLocalHTTP: false)
        #expect(configuration.baseURL.host == "api.example.com")
        #expect(throws: ConfigurationError.missing("APIHost")) { try APIConfiguration(infoDictionary: ["APIScheme": "https"], allowsInsecureLocalHTTP: false) }
        #expect(throws: ConfigurationError.missing("APIScheme")) { try APIConfiguration(infoDictionary: [:], allowsInsecureLocalHTTP: false) }
    }
}

@Suite("Problem details")
struct ProblemTests {
    let validation = """
        {"type":"urn:problem-type:validation_failed","title":"The request is not valid","status":422,"code":"validation_failed",
         "errors":[{"path":"title","message":"Title is required"},{"path":"body","message":"Too long"}]}
        """

    @Test("a full validation problem decodes, with its field errors")
    func decodes() throws {
        let problem = try #require(ProblemDetails.decode(Data(validation.utf8)))
        #expect(problem.code == ProblemDetails.validationFailed && problem.status == 422)
        #expect(problem.errors == [.init(path: "title", message: "Title is required"), .init(path: "body", message: "Too long")])
        let error = AppError.problem(problem)
        #expect(error.fieldErrors == ["title": "Title is required", "body": "Too long"])
        #expect(error.message == "The request is not valid: Title is required")
    }

    @Test("a code this client has never seen is kept, not rejected")
    func unknownCode() throws {
        let body = #"{"type":"urn:problem-type:quota_exceeded","title":"Quota","status":429,"code":"quota_exceeded","extra":"ignored"}"#
        #expect(try #require(ProblemDetails.decode(Data(body.utf8))).code == "quota_exceeded")
    }

    @Test("anything that is not a problem document is nil", arguments: ["", "<html>502</html>", "{}", #"{"code":1}"#, "[]", "null"])
    func notAProblem(body: String) {
        #expect(ProblemDetails.decode(Data(body.utf8)) == nil)
    }

    @Test("the generated Problem type converts to the app's, including an unknown code")
    func generated() {
        let generated = Components.Schemas.Problem(_type: "urn:problem-type:x", title: "T", status: 404, detail: "d", code: "not_found", errors: nil)
        let problem = ProblemDetails(generated)
        #expect(problem == ProblemDetails(type: "urn:problem-type:x", title: "T", status: 404, detail: "d", code: "not_found", errors: nil))
        #expect(AppError.problem(problem).message == "T: d")
    }

    @Test("error messages never contain a token or a password-shaped value")
    func messages() {
        let errors: [AppError] = [.unauthenticated, .invalidCredentials, .rateLimited, .network("-1009"), .invalidResponse("x"), .unexpectedStatus(500), .storage(-25300), .configuration("c")]
        for error in errors { #expect(!error.message.isEmpty && !error.message.contains(Fixture.token)) }
    }
}

@Suite("Authentication state")
struct AuthStateTests {
    let session = SessionInfo(user: .init(id: "u1", email: "a@example.test", name: "A"), expiresAt: Date(timeIntervalSince1970: 2_000_000_000))
    let failure = AppError.network("-1009")

    @Test("every transition")
    func transitions() {
        let table: [(AuthState, AuthEvent, AuthState)] = [
            (.launching, .nothingStored, .signedOut(.none)),
            (.launching, .restored(session), .signedIn(session)),
            (.launching, .restoreFailed(failure), .unconfirmed(failure)),
            (.launching, .authenticationFailed, .signedOut(.sessionEnded)),
            (.unconfirmed(failure), .restored(session), .signedIn(session)),
            (.unconfirmed(failure), .authenticationFailed, .signedOut(.sessionEnded)),
            (.signedOut(.none), .signedIn(session), .signedIn(session)),
            (.signedOut(.sessionEnded), .signedIn(session), .signedIn(session)),
            (.signedIn(session), .signedOut(.revoked), .signedOut(.none)),
            (.signedIn(session), .signedOut(.notRevoked(failure)), .signedOut(.notRevokedOnServer)),
            (.signedIn(session), .authenticationFailed, .signedOut(.sessionEnded)),
            (.signedOut(.none), .authenticationFailed, .signedOut(.none)),
            (.signedOut(.notRevokedOnServer), .authenticationFailed, .signedOut(.notRevokedOnServer)),
        ]
        for (from, event, expected) in table { #expect(from.reduced(by: event) == expected, "\(from) + \(event)") }
    }

    @Test("only a signed-in state has a session")
    func sessionAccessor() {
        #expect(AuthState.signedIn(session).session == session)
        #expect(AuthState.launching.session == nil && AuthState.signedOut(.none).session == nil && AuthState.unconfirmed(failure).session == nil)
    }
}
