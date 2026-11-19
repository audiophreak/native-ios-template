import APIClient
import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

public struct Item: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var body: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: String, title: String, body: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(_ generated: Components.Schemas.Item) {
        self.init(id: generated.id, title: generated.title, body: generated.body, createdAt: generated.createdAt, updatedAt: generated.updatedAt)
    }
}

/// The application's own API (`/api/v1`), through the typed client generated from ios/Contract/openapi.json.
/// Every method either returns what the contract promises or throws an `AppError`; the generated client's own
/// errors, transport failures and unexpected answers are all translated here, in one place.
public struct APIService: Sendable {
    private let client: any APIProtocol

    public init(client: any APIProtocol) { self.client = client }

    /// The production wiring: the URLSession transport, and the bearer middleware that adds the stored token.
    public static func live(
        configuration: APIConfiguration, session: URLSession, tokenStore: TokenStore,
        onAuthenticationFailure: @escaping @Sendable () async -> Void
    ) -> APIService {
        let client = Client(
            serverURL: configuration.baseURL,
            configuration: .init(dateTranscoder: FlexibleISO8601DateTranscoder()),
            transport: URLSessionTransport(configuration: .init(session: session)),
            middlewares: [BearerAuthMiddleware(apiBaseURL: configuration.baseURL, tokenStore: tokenStore, onAuthenticationFailure: onAuthenticationFailure)]
        )
        return APIService(client: client)
    }

    public func currentSession() async throws -> SessionInfo {
        try await call {
            switch try await client.getSession() {
            case .ok(let ok):
                let session = try ok.body.json
                return SessionInfo(
                    user: AuthenticatedUser(id: session.user.id, email: session.user.email, name: session.user.name),
                    expiresAt: session.session.expiresAt
                )
            case .unauthorized: throw AppError.unauthenticated
            case .internalServerError(let failure): throw try Self.problem(failure.body.applicationProblemJson)
            case .undocumented(let status, _): throw AppError.unexpectedStatus(status)
            }
        }
    }

    public func listItems(limit: Int = 20, offset: Int = 0) async throws -> [Item] {
        try await call {
            switch try await client.listItems(query: .init(limit: limit, offset: offset)) {
            case .ok(let ok): return try ok.body.json.items.map(Item.init)
            case .unauthorized: throw AppError.unauthenticated
            case .unprocessableContent(let failure): throw try Self.problem(failure.body.applicationProblemJson)
            case .internalServerError(let failure): throw try Self.problem(failure.body.applicationProblemJson)
            case .undocumented(let status, _): throw AppError.unexpectedStatus(status)
            }
        }
    }

    public func item(id: String) async throws -> Item {
        try await call {
            switch try await client.getItem(path: .init(id: id)) {
            case .ok(let ok): return Item(try ok.body.json)
            case .unauthorized: throw AppError.unauthenticated
            case .notFound(let failure): throw try Self.problem(failure.body.applicationProblemJson)
            case .internalServerError(let failure): throw try Self.problem(failure.body.applicationProblemJson)
            case .undocumented(let status, _): throw AppError.unexpectedStatus(status)
            }
        }
    }

    public func createItem(title: String, body: String) async throws -> Item {
        try await call {
            switch try await client.createItem(body: .json(.init(title: title, body: body))) {
            case .created(let created): return Item(try created.body.json)
            case .unauthorized: throw AppError.unauthenticated
            case .badRequest(let failure): throw try Self.problem(failure.body.applicationProblemJson)
            case .forbidden(let failure): throw try Self.problem(failure.body.applicationProblemJson)
            case .contentTooLarge(let failure): throw try Self.problem(failure.body.applicationProblemJson)
            case .unsupportedMediaType(let failure): throw try Self.problem(failure.body.applicationProblemJson)
            case .unprocessableContent(let failure): throw try Self.problem(failure.body.applicationProblemJson)
            case .internalServerError(let failure): throw try Self.problem(failure.body.applicationProblemJson)
            case .undocumented(let status, _): throw AppError.unexpectedStatus(status)
            }
        }
    }

    public func updateItem(id: String, title: String?, body: String?) async throws -> Item {
        try await call {
            switch try await client.updateItem(path: .init(id: id), body: .json(.init(title: title, body: body))) {
            case .ok(let ok): return Item(try ok.body.json)
            case .unauthorized: throw AppError.unauthenticated
            case .badRequest(let failure): throw try Self.problem(failure.body.applicationProblemJson)
            case .forbidden(let failure): throw try Self.problem(failure.body.applicationProblemJson)
            case .notFound(let failure): throw try Self.problem(failure.body.applicationProblemJson)
            case .contentTooLarge(let failure): throw try Self.problem(failure.body.applicationProblemJson)
            case .unsupportedMediaType(let failure): throw try Self.problem(failure.body.applicationProblemJson)
            case .unprocessableContent(let failure): throw try Self.problem(failure.body.applicationProblemJson)
            case .internalServerError(let failure): throw try Self.problem(failure.body.applicationProblemJson)
            case .undocumented(let status, _): throw AppError.unexpectedStatus(status)
            }
        }
    }

    public func deleteItem(id: String) async throws {
        try await call {
            switch try await client.deleteItem(path: .init(id: id)) {
            case .noContent: return
            case .unauthorized: throw AppError.unauthenticated
            case .forbidden(let failure): throw try Self.problem(failure.body.applicationProblemJson)
            case .notFound(let failure): throw try Self.problem(failure.body.applicationProblemJson)
            case .internalServerError(let failure): throw try Self.problem(failure.body.applicationProblemJson)
            case .undocumented(let status, _): throw AppError.unexpectedStatus(status)
            }
        }
    }

    private static func problem(_ generated: Components.Schemas.Problem) -> AppError {
        .problem(ProblemDetails(generated))
    }

    /// Runs one call and translates what the generated client throws: a transport failure is a network error,
    /// a response the client could not decode is an invalid response, and an `AppError` passes through.
    private func call<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as AppError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ClientError {
            if let urlError = error.underlyingError as? URLError { throw AppError.network("\(urlError.code.rawValue)") }
            if let app = error.underlyingError as? AppError { throw app }
            throw AppError.invalidResponse("the response did not match the API contract")
        } catch {
            throw AppError.invalidResponse("unexpected failure")
        }
    }
}
