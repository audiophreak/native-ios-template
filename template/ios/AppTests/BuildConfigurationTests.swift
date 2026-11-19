import Foundation
import Testing

@testable import AppCore

/// The host app's own Info.plist, as built: the API address comes from configuration, and the Debug build is the
/// only one with a network-security exception, and only for local addresses. (ios/scripts/check-release-config.sh
/// proves the Release plist has none.)
@Suite("Build configuration of the host app")
struct BuildConfigurationTests {
    let info = Bundle.main.infoDictionary ?? [:]

    @Test("the API address is configuration and passes validation")
    func address() throws {
        let configuration = try APIConfiguration.fromMainBundle()
        #expect(configuration.baseURL.user == nil && configuration.baseURL.password == nil)
        #expect(["http", "https"].contains(configuration.baseURL.scheme))
    }

    @Test("App Transport Security is never disabled; only the narrow local-network exception exists, and only in Debug")
    func ats() throws {
        let ats = info["NSAppTransportSecurity"] as? [String: Any]
        #expect(ats?["NSAllowsArbitraryLoads"] == nil)
        #expect(ats?["NSAllowsArbitraryLoadsInWebContent"] == nil)
        #expect(ats?["NSExceptionDomains"] == nil)
        #if DEBUG
        #expect(Set(ats?.keys.map { $0 } ?? []) == ["NSAllowsLocalNetworking"])
        #else
        #expect(ats == nil)
        #endif
    }

    @Test("the bundle carries no credential-looking value")
    func noSecrets() {
        let flattened = "\(info)".lowercased()
        for word in ["password", "secret", "apikey", "api_key", "bearer "] { #expect(!flattened.contains(word), "\(word)") }
    }
}
