import APIClient
import Foundation
import Testing

@testable import AppCore

/// The generated client is only as good as the contract it came from. These tests tie the committed contract,
/// its recorded checksum and what the app relies on together, so a contract change that the app is not ready for
/// fails here rather than in a person's hands.
@Suite("API contract compatibility")
struct ContractTests {
    static let contractURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "Contract")

    func contract() throws -> [String: Any] {
        let data = try Data(contentsOf: Self.contractURL.appending(path: "openapi.json"))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("it is OpenAPI 3.1, API version 1, and its checksum is the recorded one")
    func identity() throws {
        let document = try contract()
        #expect((document["openapi"] as? String)?.hasPrefix("3.1") == true)
        #expect(((document["info"] as? [String: Any])?["version"] as? String)?.hasPrefix("1.") == true)
        let recorded = try String(contentsOf: Self.contractURL.appending(path: "openapi.sha256"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let data = try Data(contentsOf: Self.contractURL.appending(path: "openapi.json"))
        #expect(Checksum.sha256Hex(data) == recorded)
    }

    @Test("every operation the app calls exists in the contract, and the protected ones need the bearer scheme")
    func operations() throws {
        let paths = try #require(try contract()["paths"] as? [String: [String: Any]])
        var found: [String: [String: Any]] = [:]
        for item in paths.values {
            for case let (method, value as [String: Any]) in item where ["get", "post", "patch", "delete", "put"].contains(method) {
                if let id = value["operationId"] as? String { found[id] = value }
            }
        }
        for used in ["getSession", "listItems", "createItem", "getItem", "updateItem", "deleteItem"] {
            let operation = try #require(found[used], "the contract no longer has \(used)")
            let security = operation["security"] as? [[String: Any]]
            #expect(security?.contains { $0["bearerAuth"] != nil } == true, "\(used) is not marked as needing the bearer token")
        }
        let schemes = ((try contract()["components"] as? [String: Any])?["securitySchemes"] as? [String: [String: Any]]) ?? [:]
        #expect(schemes["bearerAuth"]?["scheme"] as? String == "bearer")
    }

    @Test("every problem status the API documents is one this client maps (no response is unhandled)")
    func statuses() throws {
        let paths = try #require(try contract()["paths"] as? [String: [String: Any]])
        var statuses = Set<String>()
        for item in paths.values {
            for case let (_, value as [String: Any]) in item {
                (value["responses"] as? [String: Any])?.keys.forEach { statuses.insert($0) }
            }
        }
        #expect(statuses.isSubset(of: ["200", "201", "204", "400", "401", "403", "404", "413", "415", "422", "500"]), "new statuses: \(statuses)")
    }

    @Test("the generated Item matches what the app's model expects")
    func generatedItem() {
        let item = Components.Schemas.Item(id: "i", title: "t", body: "b", createdAt: .distantPast, updatedAt: .distantFuture)
        #expect(Item(item) == Item(id: "i", title: "t", body: "b", createdAt: .distantPast, updatedAt: .distantFuture))
    }
}

import CryptoKit

enum Checksum {
    static func sha256Hex(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
}
