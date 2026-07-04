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
    private static let githubTokenAccount = "githubToken"
    private static let desktopSessionTokenAccount = "desktopSessionToken"

    @discardableResult
    static func saveGitHubToken(_ token: String) -> Bool {
        saveToken(token, account: githubTokenAccount)
    }

    static func loadGitHubToken() -> String? {
        loadToken(account: githubTokenAccount)
    }

    static func deleteGitHubToken() {
        deleteToken(account: githubTokenAccount)
    }

    static func hasGitHubToken() -> Bool {
        loadGitHubToken() != nil
    }

    @discardableResult
    static func saveDesktopSessionToken(_ token: String) -> Bool {
        saveToken(token, account: desktopSessionTokenAccount)
    }

    static func loadDesktopSessionToken() -> String? {
        loadToken(account: desktopSessionTokenAccount)
    }

    static func deleteDesktopSessionToken() {
        deleteToken(account: desktopSessionTokenAccount)
    }

    private static func saveToken(_ token: String, account: String) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }

        // Delete any existing item first — avoids update conflicts in simulator
        deleteToken(account: account)

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

    private static func loadToken(account: String) -> String? {
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

    private static func deleteToken(account: String) {
        let query: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
