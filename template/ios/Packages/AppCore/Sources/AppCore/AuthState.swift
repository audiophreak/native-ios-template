import Foundation

/// Why the app is signed out. Only the reasons that change what the person is told.
public enum SignedOutReason: Equatable, Sendable {
    /// Nothing is stored: a fresh install, or the person signed out.
    case none
    /// The server no longer accepts the stored session (revoked, expired, signed out elsewhere).
    case sessionEnded
    /// The person signed out but the server could not be told; the session there is valid until it expires.
    case notRevokedOnServer
}

public enum AuthState: Equatable, Sendable {
    /// The app has started and has not yet looked at the Keychain or asked the server.
    case launching
    case signedOut(SignedOutReason)
    case signedIn(SessionInfo)
    /// A token is stored but the server could not be reached to confirm it: the token is kept, nothing is shown.
    case unconfirmed(AppError)
}

public enum AuthEvent: Equatable, Sendable {
    /// A stored token was confirmed by the server.
    case restored(SessionInfo)
    /// Nothing stored.
    case nothingStored
    /// A stored token exists but the server could not be reached.
    case restoreFailed(AppError)
    case signedIn(SessionInfo)
    case signedOut(SignOutOutcome)
    /// The server answered 401 to a request that carried the token.
    case authenticationFailed
}

extension AuthState {
    /// The whole state machine, in one pure function so it can be tested exhaustively.
    public func reduced(by event: AuthEvent) -> AuthState {
        switch event {
        case .restored(let session), .signedIn(let session): return .signedIn(session)
        case .nothingStored: return .signedOut(.none)
        case .restoreFailed(let error): return .unconfirmed(error)
        case .signedOut(.revoked): return .signedOut(.none)
        case .signedOut(.notRevoked): return .signedOut(.notRevokedOnServer)
        case .authenticationFailed:
            // A 401 while already signed out changes nothing worth saying.
            if case .signedOut = self { return self }
            return .signedOut(.sessionEnded)
        }
    }

    public var session: SessionInfo? {
        if case .signedIn(let session) = self { return session }
        return nil
    }
}
