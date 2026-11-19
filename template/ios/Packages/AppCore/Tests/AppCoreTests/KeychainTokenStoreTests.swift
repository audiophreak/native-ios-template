import Foundation
import Testing

@testable import AppCore

// The real Keychain tests are in the app's test target (AppTests/KeychainTokenStoreTests.swift): an unhosted test
// process has no Keychain entitlement. This is the stand-in the other tests use, held to the same contract.
@Suite("In-memory token store (the Keychain stand-in)")
struct InMemoryTokenStoreTests {
    @Test("save, read, replace, clear; clearing nothing is fine")
    func contract() throws {
        let store = InMemoryTokenStore()
        #expect(try store.load() == nil)
        try store.save("one")
        #expect(try store.load() == "one")
        try store.save("two")
        #expect(try store.load() == "two")
        try store.clear()
        #expect(try store.load() == nil)
        try store.clear()
    }

    @Test("concurrent writers never corrupt it")
    func concurrency() async throws {
        let store = InMemoryTokenStore()
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<200 { group.addTask { try? store.save("token-\(index)") } }
        }
        #expect(try store.load()?.hasPrefix("token-") == true)
    }
}
