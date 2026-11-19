import Foundation
import Observation

/// Everything the app needs that is wired together once: the configuration, the Keychain, the networking
/// session, and the two services built on them.
public struct AppEnvironment: Sendable {
    public let configuration: APIConfiguration
    public let tokenStore: TokenStore
    public let auth: AuthService
    public let api: APIService
    let failures: AuthFailureRelay

    public init(configuration: APIConfiguration, tokenStore: TokenStore, session: URLSession = Networking.makeSession()) {
        let relay = AuthFailureRelay()
        self.configuration = configuration
        self.tokenStore = tokenStore
        self.failures = relay
        self.auth = AuthService(configuration: configuration, session: session, tokenStore: tokenStore)
        self.api = .live(configuration: configuration, session: session, tokenStore: tokenStore) { await relay.fire() }
    }

    /// The real app: the Keychain, scoped to this app's bundle identifier.
    public static func live(bundle: Bundle = .main) throws -> AppEnvironment {
        let service = (bundle.bundleIdentifier ?? "app") + ".session"
        return AppEnvironment(configuration: try .fromMainBundle(bundle), tokenStore: KeychainTokenStore(service: service))
    }
}

/// Connects the middleware (which sees a 401) to the model (which owns the state) without a reference cycle.
final class AuthFailureRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () async -> Void)?

    func set(_ handler: @escaping @Sendable () async -> Void) { lock.withLock { self.handler = handler } }
    func fire() async {
        let current = lock.withLock { handler }
        await current?()
    }
}

/// The signed-in or signed-out state of the app, and the actions that change it.
@MainActor
@Observable
public final class AppModel {
    public private(set) var state: AuthState = .launching
    public private(set) var isWorking = false
    public private(set) var lastError: AppError?

    public let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
        environment.failures.set { [weak self] in await self?.apply(.authenticationFailed) }
    }

    func apply(_ event: AuthEvent) { state = state.reduced(by: event) }

    /// Called once at launch: is there a stored session, and does the server still accept it?
    public func restore() async {
        do {
            guard try environment.tokenStore.load() != nil else { return apply(.nothingStored) }
            apply(.restored(try await environment.api.currentSession()))
        } catch AppError.unauthenticated {
            try? environment.tokenStore.clear()
            apply(.authenticationFailed)
            if state == .launching { state = .signedOut(.sessionEnded) }
        } catch let error as AppError {
            apply(.restoreFailed(error))
        } catch {
            apply(.restoreFailed(.invalidResponse("unexpected failure")))
        }
    }

    public func signIn(email: String, password: String) async {
        await perform {
            try await environment.auth.signIn(email: email, password: password)
            apply(.signedIn(try await environment.api.currentSession()))
        }
    }

    public func signUp(email: String, password: String, name: String) async {
        await perform {
            try await environment.auth.signUp(email: email, password: password, name: name)
            apply(.signedIn(try await environment.api.currentSession()))
        }
    }

    public func signOut() async {
        await perform {
            apply(.signedOut(try await environment.auth.signOut()))
        }
    }

    public func dismissError() { lastError = nil }

    private func perform(_ work: () async throws -> Void) async {
        isWorking = true
        lastError = nil
        defer { isWorking = false }
        do {
            try await work()
        } catch AppError.unauthenticated {
            apply(.authenticationFailed)
        } catch let error as AppError {
            lastError = error
        } catch is CancellationError {
        } catch {
            lastError = .invalidResponse("unexpected failure")
        }
    }
}
