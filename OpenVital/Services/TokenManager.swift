import Foundation
import Security

actor TokenManager {
    private static let serviceName = "dev.openvital.api-token"
    private static let accountName = "bearer-token"

    private var cachedToken: String?

    func getToken() -> String {
        if let cached = cachedToken {
            return cached
        }
        if let stored = Self.readFromKeychain() {
            cachedToken = stored
            return stored
        }
        let newToken = Self.generateToken()
        Self.saveToKeychain(newToken)
        cachedToken = newToken
        return newToken
    }

    func regenerateToken() -> String {
        let newToken = Self.generateToken()
        Self.deleteFromKeychain()
        Self.saveToKeychain(newToken)
        cachedToken = newToken
        return newToken
    }

    func validate(_ token: String?) -> Bool {
        guard let token, !token.isEmpty else { return false }
        return token == getToken()
    }

    // MARK: - Keychain Operations

    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    private static func saveToKeychain(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func readFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: accountName,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
