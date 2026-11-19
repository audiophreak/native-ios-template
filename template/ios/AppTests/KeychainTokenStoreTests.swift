import Foundation
import Security
import Testing

@testable import AppCore

/// These run inside the app on the iOS Simulator (they are in the app's test target, hosted by the app): an
/// unhosted test process has no Keychain entitlement and every call fails with -34018. Every test uses its own
/// service name and removes what it stored.
@Suite("Keychain token store")
struct KeychainTokenStoreTests {
    let service = "tests.\(UUID().uuidString)"
    let token = "dGVzdC10b2tlbi12YWx1ZQ.c2lnbmF0dXJlLXZhbHVl"  // a made-up shape, not a credential

    private func attributes(of store: KeychainTokenStore) -> [String: Any]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "session-token",
            kSecReturnAttributes as String: kCFBooleanTrue as Any,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? [String: Any]
    }

    @Test("nothing stored reads as nil")
    func empty() throws {
        #expect(try KeychainTokenStore(service: service).load() == nil)
    }

    @Test("save, read, replace, delete")
    func roundTrip() throws {
        let store = KeychainTokenStore(service: service)
        defer { try? store.clear() }
        try store.save(token)
        #expect(try store.load() == token)
        try store.save("cm90YXRlZC10b2tlbi12YWx1ZQ.cm90YXRlZC1zaWduYXR1cmU")  // a rotated token replaces, not duplicates
        #expect(try store.load() == "cm90YXRlZC10b2tlbi12YWx1ZQ.cm90YXRlZC1zaWduYXR1cmU")
        try store.clear()
        #expect(try store.load() == nil)
        try store.clear()  // deleting what is not there is not an error
    }

    @Test("the item is device-local, unlocked-only and not synchronised")
    func attributesAreRestrictive() throws {
        let store = KeychainTokenStore(service: service)
        defer { try? store.clear() }
        try store.save(token)
        let stored = try #require(attributes(of: store))
        #expect(stored[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect((stored[kSecAttrSynchronizable as String] as? Bool ?? false) == false)
        #expect(stored[kSecAttrService as String] as? String == service)  // the item is the one this store wrote, under this service
        #expect(stored[kSecAttrAccount as String] as? String == "session-token")
    }

    @Test("two services do not see each other's token")
    func isolation() throws {
        let one = KeychainTokenStore(service: service)
        let two = KeychainTokenStore(service: service + ".other")
        defer { try? one.clear(); try? two.clear() }
        try one.save(token)
        #expect(try two.load() == nil)
    }

    @Test("the token is not in UserDefaults, not in the app's preference files and not in a description of the store")
    func notElsewhere() throws {
        let store = KeychainTokenStore(service: service)
        defer { try? store.clear() }
        try store.save(token)
        #expect(!"\(UserDefaults.standard.dictionaryRepresentation())".contains(token))
        #expect(!"\(store)".contains(token) && !String(reflecting: store).contains(token))
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        let preferences = library.appending(path: "Preferences")
        for file in (try? FileManager.default.contentsOfDirectory(at: preferences, includingPropertiesForKeys: nil)) ?? [] {
            #expect(!String(decoding: (try? Data(contentsOf: file)) ?? Data(), as: UTF8.self).contains(token), "\(file.lastPathComponent)")
        }
    }
}
