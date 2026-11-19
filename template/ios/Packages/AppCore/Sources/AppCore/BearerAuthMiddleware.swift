import Foundation
import HTTPTypes
import OpenAPIRuntime

/// Adds `Authorization: Bearer <token>` to the generated client's requests, and reacts to what the server says
/// about that token:
///
/// - A `401` problem on a request that carried a token means the server no longer accepts the session
///   (signed out elsewhere, revoked, expired). The local credential is removed and `onAuthenticationFailure`
///   runs, so the app returns to the signed-out state.
/// - A `set-auth-token` header (a rotated session) replaces the stored token.
///
/// The token is only ever sent to the configured API origin; a request for any other base URL gets none.
public struct BearerAuthMiddleware: ClientMiddleware {
    private let apiBaseURL: URL
    private let tokenStore: TokenStore
    private let onAuthenticationFailure: @Sendable () async -> Void

    public init(apiBaseURL: URL, tokenStore: TokenStore, onAuthenticationFailure: @escaping @Sendable () async -> Void) {
        self.apiBaseURL = apiBaseURL
        self.tokenStore = tokenStore
        self.onAuthenticationFailure = onAuthenticationFailure
    }

    public func intercept(
        _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        var sentToken = false
        if Self.sameOrigin(baseURL, apiBaseURL), let token = try? tokenStore.load() {
            request.headerFields[.authorization] = "Bearer \(token)"
            sentToken = true
        }
        let (response, responseBody) = try await next(request, body, baseURL)
        if let rotated = response.headerFields[HTTPField.Name(AuthService.tokenHeader)!], AuthService.isPlausible(rotated) {
            try? tokenStore.save(rotated)
        }
        if sentToken, response.status.code == 401, response.headerFields[.contentType]?.hasPrefix("application/problem+json") == true {
            try? tokenStore.clear()
            await onAuthenticationFailure()
        }
        return (response, responseBody)
    }

    static func sameOrigin(_ a: URL, _ b: URL) -> Bool {
        a.scheme?.lowercased() == b.scheme?.lowercased() && a.host?.lowercased() == b.host?.lowercased()
            && (a.port ?? Self.defaultPort(a)) == (b.port ?? Self.defaultPort(b))
    }

    private static func defaultPort(_ url: URL) -> Int { url.scheme?.lowercased() == "https" ? 443 : 80 }
}
