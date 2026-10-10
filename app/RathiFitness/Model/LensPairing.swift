import Foundation
import Security

/// The phone's key to the relay room, and how it arrives.
///
/// The key is `FITNESS_PHONE_KEY` in `~/RIA/.env`; `bin/pair-phone` (in
/// ria-ar-feed) shows it as a QR in the Mac's terminal, and Settings → Glasses
/// → Pair reads it with the LIVE camera scanner the Pass editor uses — never
/// from a screenshot, because a screenshot of a key is a copy of it. It is
/// kept in the Keychain, this device only, and never in source.
enum LensPairing {

    /// What the pairing QR says: `rflens1:<key>`, optionally followed by
    /// `#<fragment>` — the Web App's own URL fragment (`k=…&lk=…`), which lets
    /// Settings offer "Add to glasses". The prefix is REQUIRED: the scanner
    /// also reads gym passes, and storing one replaces a good key (found in
    /// review).
    static let prefix = "rflens1:"

    struct Paired: Equatable {
        var key: String
        var fragment: String?
    }

    static func parse(_ text: String) -> Paired? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard body.hasPrefix(prefix) else { return nil }
        body.removeFirst(prefix.count)
        var fragment: String?
        if let hash = body.firstIndex(of: "#") {
            fragment = String(body[body.index(after: hash)...])
            body = String(body[..<hash])
            if fragment?.isEmpty == true { fragment = nil }
        }
        guard isKey(body) else { return nil }
        if let fragment, fragment.contains(where: { $0.isWhitespace }) { return nil }
        return Paired(key: body, fragment: fragment)
    }

    /// RFC 3986 unreserved characters only, and long enough to be a secret.
    /// Anything else scanned — a gym pass, a URL — is not a key.
    static func isKey(_ s: String) -> Bool {
        (16...256).contains(s.count) && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "-._~".contains($0)) }
    }

    // MARK: - Add to glasses

    static let webAppURL = "https://feed.app.ishanrathi.com/"
    static let webAppName = "Fitness"

    /// The Meta AI deep link that adds the Web App — the SAME encoding as
    /// RIA's `bin/glasses-url` (pinned by `LensPairingTests`): every character
    /// but RFC 3986 unreserved percent-encoded, `: / ? & # =` included, because
    /// Meta AI does not recognise anything looser.
    static func addToGlasses(fragment: String) -> URL? {
        let url = webAppURL + "#" + fragment
        return URL(string: "fb-viewapp://web_app_deep_link?appName=\(encode(webAppName))&appUrl=\(encode(url))")
    }

    static func encode(_ s: String) -> String {
        var out = ""
        for byte in Array(s.utf8) {
            let c = Character(UnicodeScalar(byte))
            if byte < 0x80, c.isLetter || c.isNumber || "-._~".contains(c) {
                out.append(c)
            } else {
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }
}

/// The two secrets pairing leaves on the phone, in the Keychain, this device
/// only (`AfterFirstUnlockThisDeviceOnly`: readable while locked, which a phone
/// in a pocket is, and never in a backup).
enum LensKey {
    private static let service = "com.rathi.fitness.lens"

    static var phoneKey: String? { read("phone-key") }
    static var webAppFragment: String? { read("web-app-fragment") }

    @discardableResult
    static func store(_ paired: LensPairing.Paired) -> Bool {
        guard write("phone-key", paired.key) else { return false }
        if let fragment = paired.fragment { write("web-app-fragment", fragment) } else { delete("web-app-fragment") }
        return true
    }

    static func forget() {
        delete("phone-key")
        delete("web-app-fragment")
    }

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func read(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func write(_ account: String, _ value: String) -> Bool {
        delete(account)
        var q = query(account)
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    private static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
