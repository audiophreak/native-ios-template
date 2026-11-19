import Foundation

public enum ConfigurationError: Error, Equatable, Sendable {
    case missing(String)
    case invalid(String)
}

/// Where the API is. It is configuration, never code: the Info.plist carries `APIScheme` and `APIHost`, which
/// come from the build configuration (ios/Config/*.xcconfig). A release build only ever accepts https.
public struct APIConfiguration: Sendable, Equatable {
    public let baseURL: URL

    /// - Parameter allowsInsecureLocalHTTP: true only in Debug builds. Even then, `http` is accepted for
    ///   `localhost`, loopback addresses and `*.local` names and for nothing else.
    public init(scheme: String, host: String, allowsInsecureLocalHTTP: Bool) throws {
        guard !scheme.isEmpty else { throw ConfigurationError.missing("APIScheme") }
        guard !host.isEmpty else { throw ConfigurationError.missing("APIHost") }
        var components = URLComponents()
        components.scheme = scheme.lowercased()
        // `host` may carry a port ("localhost:3000"); anything that could hide a credential or path is refused below.
        guard let parsed = URLComponents(string: "\(scheme)://\(host)"), parsed.user == nil, parsed.password == nil,
            parsed.query == nil, parsed.fragment == nil, parsed.path.isEmpty || parsed.path == "/",
            let parsedHost = parsed.host, !parsedHost.isEmpty
        else { throw ConfigurationError.invalid("the API address must be a bare host with an optional port") }
        switch scheme.lowercased() {
        case "https": break
        case "http":
            guard allowsInsecureLocalHTTP, Self.isLocal(parsedHost) else {
                throw ConfigurationError.invalid("http is only allowed for a local address in a Debug build")
            }
        default: throw ConfigurationError.invalid("the API scheme must be https")
        }
        components.host = parsedHost
        components.port = parsed.port
        guard let url = components.url else { throw ConfigurationError.invalid("the API address is not a valid URL") }
        self.baseURL = url
    }

    public init(infoDictionary: [String: Any], allowsInsecureLocalHTTP: Bool) throws {
        guard let scheme = infoDictionary["APIScheme"] as? String else { throw ConfigurationError.missing("APIScheme") }
        guard let host = infoDictionary["APIHost"] as? String else { throw ConfigurationError.missing("APIHost") }
        try self.init(scheme: scheme, host: host, allowsInsecureLocalHTTP: allowsInsecureLocalHTTP)
    }

    /// Reads the app's Info.plist; the Debug build is the only one that may use cleartext to a local address.
    public static func fromMainBundle(_ bundle: Bundle = .main) throws -> APIConfiguration {
        #if DEBUG
        let insecure = true
        #else
        let insecure = false
        #endif
        return try APIConfiguration(infoDictionary: bundle.infoDictionary ?? [:], allowsInsecureLocalHTTP: insecure)
    }

    static func isLocal(_ host: String) -> Bool {
        let lower = host.lowercased()
        return lower == "localhost" || lower == "127.0.0.1" || lower == "::1" || lower == "[::1]" || lower.hasSuffix(".local")
    }
}
