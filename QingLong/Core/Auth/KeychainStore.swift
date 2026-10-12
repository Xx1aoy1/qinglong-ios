//
//  KeychainStore.swift
//  QingLong
//
//  Token 等敏感信息的持久化。UserDefaults 明文可被备份提取，不用于存放 Token。
//

import Foundation
import Security

enum KeychainStore {

    private static let service = "com.qinglong.mobile.credentials"

    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)
        case dataConversionFailed

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                return "钥匙串操作失败（OSStatus \(status)）"
            case .dataConversionFailed:
                return "钥匙串数据格式异常"
            }
        }
    }

    // MARK: - 基础操作

    static func set(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataConversionFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }

        if status == errSecItemNotFound {
            var insertQuery = query
            insertQuery.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
            return
        }

        throw KeychainError.unexpectedStatus(status)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    @discardableResult
    static func remove(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - 业务封装

    static func tokenKey(for serverID: UUID) -> String {
        "token.\(serverID.uuidString)"
    }

    static func saveToken(_ token: String, for serverID: UUID) {
        try? set(token, for: tokenKey(for: serverID))
    }

    static func token(for serverID: UUID) -> String? {
        get(tokenKey(for: serverID))
    }

    static func removeToken(for serverID: UUID) {
        remove(tokenKey(for: serverID))
    }
}
