import Foundation

/// URLSession settings for talking to the API: no cookies (a native client authenticates with its bearer
/// token only), no cache of authenticated answers, bounded timeouts and no automatic redirects, so a
/// credential can never be forwarded to another address. Certificate validation is the system's: it is never
/// disabled and nothing is pinned.
public enum Networking {
    public static func makeSession(timeout: TimeInterval = 30) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }
}

/// Answers every redirect with "do not follow": the API never redirects, so one is a misconfiguration or an attack.
final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
