import Foundation
import Security

/// BYOK の API キーを macOS キーチェーンに保存する。設定ファイルには書かない。
enum Keychain {
    private static let service = "io.github.koebumi.apikeys"

    /// Speak という名前だったころのキーを、新しい置き場所に写す。Speak のデータを写したときに 1 回だけ呼ぶ。
    /// 別のアプリが作った項目なので、キーごとにキーチェーンへのアクセスの確認が出る。
    static func migrateLegacy() {
        let legacyService = "local.speak.app.apikeys"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var items: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
              let attributes = items as? [[String: Any]]
        else { return }
        for account in attributes.compactMap({ $0[kSecAttrAccount as String] as? String }) where get(account) == nil {
            set(get(account, service: legacyService), for: account)
        }
    }

    static func get(_ account: String) -> String? {
        get(account, service: service)
    }

    private static func get(_ account: String, service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    static func set(_ value: String?, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
