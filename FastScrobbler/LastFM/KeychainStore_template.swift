import Foundation
import Security

enum KeychainStore {
    // Keychain access groups include the Team ID prefix:
    //   <TEAMID>.<group-identifier>
    //
    // This template intentionally does NOT embed a Team ID so it is safe to commit.
    //
    // If you want the app + extensions to share Keychain items, set the same access group
    // string for each target (entitlements + Info.plist):
    //   - Add it to each target's `keychain-access-groups` entitlement
    //   - Set `KEYCHAIN_ACCESS_GROUP` in each target's Info.plist (or via a build setting)
    private static let accessGroupInfoPlistKey = "KEYCHAIN_ACCESS_GROUP"

    private static func resolvedAccessGroup() -> String? {
        let raw = Bundle.main.object(forInfoDictionaryKey: accessGroupInfoPlistKey) as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func readString(service: String, account: String) -> String? {
        let accessGroup = resolvedAccessGroup()
        if let accessGroup, let value = readString(service: service, account: account, accessGroup: accessGroup) {
            return value
        }
        let legacyValue = readString(service: service, account: account, accessGroup: nil)
        if let legacyValue, let accessGroup {
            // Best-effort migration to the shared access group (so extensions can read it too).
            do {
                try writeString(legacyValue, service: service, account: account, accessGroup: accessGroup)
                delete(service: service, account: account, accessGroup: nil)
            } catch {
                // Ignore: keep legacy value readable for the app.
            }
        }
        return legacyValue
    }

    private static func readString(service: String, account: String, accessGroup: String?) -> String? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func writeString(_ value: String, service: String, account: String) throws {
        if let accessGroup = resolvedAccessGroup() {
            do {
                try writeString(value, service: service, account: account, accessGroup: accessGroup)
                return
            } catch {
                let ns = error as NSError
                if ns.domain == NSOSStatusErrorDomain, ns.code == Int(errSecMissingEntitlement) {
                    // Fall through to legacy write without the access group.
                } else {
                    throw error
                }
            }
        }
        try writeString(value, service: service, account: account, accessGroup: nil)
    }

    private static func writeString(_ value: String, service: String, account: String, accessGroup: String?) throws {
        let data = Data(value.utf8)

        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }

        let attributes: [CFString: Any] = [
            kSecValueData: data,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        if status != errSecItemNotFound {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }

        var addQuery = query
        addQuery[kSecValueData] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
        }
    }

    static func delete(service: String, account: String) {
        if let accessGroup = resolvedAccessGroup() {
            delete(service: service, account: account, accessGroup: accessGroup)
        }
        delete(service: service, account: account, accessGroup: nil)
    }

    private static func delete(service: String, account: String, accessGroup: String?) {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }
        SecItemDelete(query as CFDictionary)
    }
}
