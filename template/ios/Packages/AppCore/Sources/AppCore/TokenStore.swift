import Foundation
import Security

/// Where the session token lives between launches. The token is a credential: it is never written to
/// UserDefaults, a file, a log or an error message, and it is never shown.
public protocol TokenStore: Sendable {
    func load() throws -> String?
    func save(_ token: String) throws
    func clear() throws
}

/// The iOS Keychain, through Apple's Security framework.
///
/// - Accessible only while the device is unlocked (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`), which an
///   interactive app needs and nothing more: a background task that runs while the device is locked has no
///   token, and a restore onto another device does not carry it.
/// - Never synchronised to iCloud (`kSecAttrSynchronizable` is false), never in a backup that restores elsewhere.
public struct KeychainTokenStore: TokenStore {
    public static var accessibility: CFString { kSecAttrAccessibleWhenUnlockedThisDeviceOnly }

    private let service: String
    private let account: String

    public init(service: String, account: String = "session-token") {
        self.service = service
        self.account = account
    }

    private var identity: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    public func load() throws -> String? {
        var query = identity
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
                throw AppError.storage(Int(errSecDecode))
            }
            return token
        case errSecItemNotFound: return nil
        default: throw AppError.storage(Int(status))
        }
    }

    public func save(_ token: String) throws {
        let data = Data(token.utf8)
        let update = SecItemUpdate(identity as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch update {
        case errSecSuccess: return
        case errSecItemNotFound:
            var add = identity
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = Self.accessibility
            let status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess else { throw AppError.storage(Int(status)) }
        default: throw AppError.storage(Int(update))
        }
    }

    public func clear() throws {
        let status = SecItemDelete(identity as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AppError.storage(Int(status)) }
    }
}

/// For tests and previews: nothing is persisted.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    public init(token: String? = nil) { value = token }

    public func load() throws -> String? { lock.withLock { value } }
    public func save(_ token: String) throws { lock.withLock { value = token } }
    public func clear() throws { lock.withLock { value = nil } }
}
