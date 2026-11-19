import Foundation

/// Everything that can go wrong from the app's point of view, with text that is safe to show: it never
/// contains a token, a password or a request body.
public enum AppError: Error, Equatable, Sendable {
    /// The server answered with a problem document.
    case problem(ProblemDetails)
    /// The session is missing, expired or revoked (HTTP 401): the app returns to the signed-out state.
    case unauthenticated
    /// The e-mail or password was not accepted.
    case invalidCredentials
    /// Too many attempts; try again shortly.
    case rateLimited
    /// The device could not reach the server (offline, timeout, TLS failure, wrong address).
    case network(String)
    /// The server answered, but not with anything this client understands (malformed or unexpected response).
    case invalidResponse(String)
    /// A response that is a failure but not a documented one.
    case unexpectedStatus(Int)
    /// The Keychain refused an operation (the status is the `OSStatus`, never the data).
    case storage(Int)
    case configuration(String)

    public var message: String {
        switch self {
        case .problem(let problem):
            if let first = problem.errors?.first { return "\(problem.title): \(first.message)" }
            return problem.detail.map { "\(problem.title): \($0)" } ?? problem.title
        case .unauthenticated: return "Your session has ended. Please sign in again."
        case .invalidCredentials: return "The e-mail or password is not correct."
        case .rateLimited: return "Too many attempts. Wait a few seconds and try again."
        case .network: return "Could not reach the server. Check the connection and try again."
        case .invalidResponse: return "The server's answer could not be understood."
        case .unexpectedStatus(let status): return "The server answered with an unexpected status (\(status))."
        case .storage: return "The secure storage on this device refused the request."
        case .configuration(let reason): return "The app is not configured correctly: \(reason)"
        }
    }

    /// Field-level messages of a validation problem, by field path ("title", "body").
    public var fieldErrors: [String: String] {
        guard case .problem(let problem) = self else { return [:] }
        return Dictionary(problem.errors?.map { ($0.path, $0.message) } ?? [], uniquingKeysWith: { first, _ in first })
    }
}
