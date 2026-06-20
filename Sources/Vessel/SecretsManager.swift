import Foundation
import Security

public class SecretsManager {
    public static let shared = SecretsManager()

    private init() {}

    // MARK: - Keychain (Global Secrets)

    public func saveGlobalSecret(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw NSError(domain: "SecretsManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid value encoding"])
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.vessel.secrets"
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            status = SecItemAdd(newItem as CFDictionary, nil)
        }

        if status != errSecSuccess {
            throw NSError(domain: "SecretsManager", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain error: \(status)"])
        }
    }

    public func getGlobalSecret(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.vessel.secrets",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess, let data = dataTypeRef as? Data {
            let value = String(data: data, encoding: .utf8)
            // Memory zeroing
            zeroData(data)
            return value
        } else if status == errSecItemNotFound {
            return nil
        } else {
            throw NSError(domain: "SecretsManager", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain error: \(status)"])
        }
    }

    public func deleteGlobalSecret(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.vessel.secrets"
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw NSError(domain: "SecretsManager", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain error: \(status)"])
        }
    }

    public func getAllGlobalSecretKeys() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.vessel.secrets",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

        if status == errSecSuccess, let items = dataTypeRef as? [[String: Any]] {
            return items.compactMap { $0[kSecAttrAccount as String] as? String }
        } else if status == errSecItemNotFound {
            return []
        } else {
            throw NSError(domain: "SecretsManager", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Keychain error: \(status)"])
        }
    }

    // MARK: - Local .env File

    public func loadEnvFile(at url: URL) throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return [:]
        }

        let contents = try String(contentsOf: url, encoding: .utf8)
        return EnvParser.parse(envString: contents)
    }

    public func saveEnvFile(envVars: [String: String], at url: URL) throws {
        var contents = ""
        for (key, value) in envVars.sorted(by: { $0.key < $1.key }) {
            // Simple quoting if value contains spaces or special characters
            if value.contains(" ") || value.contains("=") {
                contents += "\(key)=\"\(value)\"\n"
            } else {
                contents += "\(key)=\(value)\n"
            }
        }

        let data = contents.data(using: .utf8)!

        // Ensure file permissions are restricted (0600)
        let attributes: [FileAttributeKey: Any] = [
            .posixPermissions: 0o600
        ]

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
            try data.write(to: url, options: .atomic)
        } else {
            FileManager.default.createFile(atPath: url.path, contents: data, attributes: attributes)
        }
    }

    // MARK: - Security Helpers

    private func zeroData(_ data: Data) {
        var mutableData = data
        let count = mutableData.count
        mutableData.withUnsafeMutableBytes { ptr in
            if let baseAddress = ptr.baseAddress {
                memset(baseAddress, 0, count)
            }
        }
    }
}
