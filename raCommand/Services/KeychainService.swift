//
//  KeychainService.swift
//  raCommand
//
//  Robust Keychain with accessibility flag so it persists
//  across simulator launches and device restarts.
//

import Foundation
import Security

enum KeychainService {
    private static let service = "com.readyaimgo.raCommand"
    private static let account = "githubToken"

    @discardableResult
    static func saveGitHubToken(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }

        // Delete any existing item first — avoids update conflicts in simulator
        deleteGitHubToken()

        let query: [String: Any] = [
            kSecClass as String:                kSecClassGenericPassword,
            kSecAttrService as String:          service,
            kSecAttrAccount as String:          account,
            kSecValueData as String:            data,
            kSecAttrAccessible as String:       kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func loadGitHubToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      service,
            kSecAttrAccount as String:      account,
            kSecReturnData as String:       true,
            kSecMatchLimit as String:       kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    static func deleteGitHubToken() {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func hasGitHubToken() -> Bool {
        loadGitHubToken() != nil
    }
}
