import Foundation
import Security

/// Thread-safe Keychain wrapper for the Anthropic API key.
enum KeychainService {

    private static let service = "com.josmall.PairwiseReminders"
    private static let account = "anthropic-api-key"

    // MARK: - Public Interface

    /// Saves the API key to the Keychain. Returns true on success.
    @discardableResult
    static func save(apiKey: String) -> Bool {
        guard let data = apiKey.data(using: .utf8) else { return false }

        // Remove existing entry first to allow updates
        delete()

        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  service,
            kSecAttrAccount:  account,
            kSecValueData:    data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Returns the stored API key, or nil if not found.
    static func load() -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8)
        else { return nil }
        return key
    }

    /// Deletes the stored API key.
    static func delete() {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// True when an API key is stored in the Keychain.
    static var hasAPIKey: Bool {
        load() != nil
    }
}
