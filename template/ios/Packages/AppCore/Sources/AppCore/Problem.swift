import APIClient
import Foundation

/// An RFC 9457 problem document as the API sends it (`application/problem+json`). `code` is the stable,
/// machine-readable identifier a client branches on. An unknown code is kept, not rejected: within v1 codes
/// are only ever added.
public struct ProblemDetails: Codable, Equatable, Sendable, Error {
    public struct FieldError: Codable, Equatable, Sendable {
        public var path: String
        public var message: String
        public init(path: String, message: String) {
            self.path = path
            self.message = message
        }
    }

    public var type: String
    public var title: String
    public var status: Int
    public var detail: String?
    public var code: String
    public var errors: [FieldError]?

    public init(type: String, title: String, status: Int, detail: String? = nil, code: String, errors: [FieldError]? = nil) {
        self.type = type
        self.title = title
        self.status = status
        self.detail = detail
        self.code = code
        self.errors = errors
    }

    public init(_ generated: Components.Schemas.Problem) {
        self.init(
            type: generated._type, title: generated.title, status: generated.status, detail: generated.detail,
            code: generated.code,
            errors: generated.errors?.map { FieldError(path: $0.path, message: $0.message) }
        )
    }

    /// Decodes a body that should be a problem document; nil for anything else (HTML from a proxy, empty bodies).
    public static func decode(_ data: Data) -> ProblemDetails? {
        try? JSONDecoder().decode(ProblemDetails.self, from: data)
    }

    public static let unauthenticated = "unauthenticated"
    public static let validationFailed = "validation_failed"
    public static let notFound = "not_found"
    public static let originNotAllowed = "origin_not_allowed"
}
