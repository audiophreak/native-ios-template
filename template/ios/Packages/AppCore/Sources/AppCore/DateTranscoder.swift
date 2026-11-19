import Foundation
import OpenAPIRuntime

/// The API writes timestamps as ISO 8601 with milliseconds (`2026-01-02T03:04:05.000Z`, what JavaScript's
/// `toISOString` produces). The generator's default transcoder reads only whole seconds, so this one accepts both.
struct FlexibleISO8601DateTranscoder: DateTranscoder {
    func encode(_ date: Date) throws -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    func decode(_ dateString: String) throws -> Date {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: dateString) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: dateString) { return date }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected an ISO 8601 date, got \(dateString.prefix(40))"))
    }
}
