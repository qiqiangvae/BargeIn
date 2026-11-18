import Foundation

/// 日程密码存在哪里。ad-hoc 签名每版都变，钥匙串把授权绑在签名身份上，
/// 所以每次更新后系统都把它当新 App 问一次；本地文件没有这条身份约束，代价是明文。
enum CredentialStoreMode: String, Codable {
    case file
    case keychain
}

/// 两种存储对上层只有一套接口；模式存在 `AppState` 里，切换时把已存的密码搬过去。
enum Credentials {
    static func secret(for id: UUID, mode: CredentialStoreMode) -> String? {
        switch mode {
        case .file:
            if let value = PasswordFile.password(for: id) { return value }
            // 老版本只往钥匙串里存：第一次用到时搬过来，用户点一次「始终允许」就够。
            // 这次授权取消也只会让本次拉取失败，密码仍留在原处，下次再试。
            guard let legacy = Keychain.password(for: id) else { return nil }
            guard PasswordFile.set(legacy, for: id) else { return legacy }
            Keychain.deletePassword(for: id)
            return legacy
        case .keychain:
            return Keychain.password(for: id)
        }
    }

    static func save(_ password: String, for id: UUID, mode: CredentialStoreMode) {
        switch mode {
        case .file:
            // 写成功才删钥匙串里的旧副本，免得切回钥匙串时复活一个旧密码。
            guard PasswordFile.set(password, for: id) else { return }
            Keychain.deletePassword(for: id)
        case .keychain:
            Keychain.setPassword(password, for: id)
        }
    }

    static func delete(for id: UUID, mode: CredentialStoreMode) {
        switch mode {
        case .file:
            PasswordFile.set(nil, for: id)
            Keychain.deletePassword(for: id)
        case .keychain:
            Keychain.deletePassword(for: id)
        }
    }

    /// 切换存储时搬已存的密码：先写新存储、读回来核对通过，再删旧存储。
    /// 返回 false 表示有密码没搬成（例如钥匙串授权被取消），密码留在原处，模式不该切。
    static func move(_ ids: [UUID], from source: CredentialStoreMode, to target: CredentialStoreMode) -> Bool {
        guard source != target else { return true }
        var movedAll = true
        for id in ids {
            guard let value = read(source, id), !value.isEmpty else { continue }
            guard write(target, value, for: id), read(target, id) == value else {
                movedAll = false
                continue
            }
            erase(source, id)
        }
        return movedAll
    }

    private static func read(_ mode: CredentialStoreMode, _ id: UUID) -> String? {
        switch mode {
        case .file: return PasswordFile.password(for: id)
        case .keychain: return Keychain.password(for: id)
        }
    }

    private static func write(_ mode: CredentialStoreMode, _ password: String, for id: UUID) -> Bool {
        switch mode {
        case .file: return PasswordFile.set(password, for: id)
        case .keychain: return Keychain.setPassword(password, for: id)
        }
    }

    private static func erase(_ mode: CredentialStoreMode, _ id: UUID) {
        switch mode {
        case .file: PasswordFile.set(nil, for: id)
        case .keychain: Keychain.deletePassword(for: id)
        }
    }
}

/// 本地密码文件：`~/.config/bargein/config.toml`，只有一个 `[passwords]` 表。
/// App 是唯一写者（手改会被整体覆盖），但读的时候手写坏行只跳过、不当错误。
enum PasswordFile {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/bargein/config.toml")
    }

    static func password(for id: UUID) -> String? {
        passwords()[id.uuidString]
    }

    @discardableResult
    static func set(_ password: String?, for id: UUID) -> Bool {
        var map = passwords()
        if let password, !password.isEmpty {
            map[id.uuidString] = password
        } else {
            map.removeValue(forKey: id.uuidString)
        }
        return write(map)
    }

    private static func passwords() -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        return parse(text)
    }

    /// 只认 `[passwords]` 下的 `键 = "值"`；别的表、注释、认不出的行都不管。
    static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var section = ""
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") {
                section = String(line.dropFirst().prefix { $0 != "]" })
                continue
            }
            guard section == "passwords",
                  let equals = line.firstIndex(of: "=")
            else { continue }
            let keyPart = line[..<equals].trimmingCharacters(in: .whitespaces)
            let valuePart = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            guard let key = key(from: keyPart), !key.isEmpty,
                  let value = string(from: valuePart)
            else { continue }
            result[key] = value
        }
        return result
    }

    static func render(_ map: [String: String]) -> String {
        var lines = [
            "# Barge In 的日程密码。由 App 写，手改会被覆盖。",
            "[passwords]",
        ]
        for (key, value) in map.sorted(by: { $0.key < $1.key }) {
            lines.append("\(quoted(key)) = \(quoted(value))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func write(_ map: [String: String]) -> Bool {
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            let temporary = directory.appendingPathComponent(".config.toml.\(UUID().uuidString.prefix(8))")
            try render(map).write(to: temporary, atomically: false, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: temporary.path
            )
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: url)
            }
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
            return true
        } catch {
            print("[bargein] credential file write failed: \(error)")
            return false
        }
    }

    // MARK: - TOML 子集

    /// 键：`"带引号的键"` 或裸键（UUID 里的 `-` 可以裸写）。
    private static func key(from text: String) -> String? {
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 {
            return unquoted(String(text.dropFirst().dropLast()))
        }
        return text.isEmpty ? nil : String(text)
    }

    /// 值只接受字符串：基本字符串（带转义）或字面量字符串（`'…'`）。
    /// 数字、布尔、数组这些不是密码，直接当认不出。
    private static func string(from text: String) -> String? {
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 {
            return unquoted(String(text.dropFirst().dropLast()))
        }
        if text.hasPrefix("'"), text.hasSuffix("'"), text.count >= 2 {
            return String(text.dropFirst().dropLast())
        }
        return nil
    }

    private static func quoted(_ raw: String) -> String {
        var out = "\""
        for scalar in raw.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    out += String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    private static func unquoted(_ raw: String) -> String? {
        var out = ""
        let scalars = Array(raw.unicodeScalars)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            index += 1
            guard scalar == "\\" else {
                out.unicodeScalars.append(scalar)
                continue
            }
            guard index < scalars.count else { return nil }
            let escape = scalars[index]
            index += 1
            switch escape {
            case "\"": out += "\""
            case "\\": out += "\\"
            case "n": out += "\n"
            case "r": out += "\r"
            case "t": out += "\t"
            case "b": out += "\u{08}"
            case "f": out += "\u{0C}"
            case "u":
                guard index + 4 <= scalars.count,
                      let value = UInt32(String(String.UnicodeScalarView(scalars[index..<(index + 4)])), radix: 16),
                      let decoded = UnicodeScalar(value)
                else { return nil }
                out.unicodeScalars.append(decoded)
                index += 4
            default:
                return nil
            }
        }
        return out
    }
}
