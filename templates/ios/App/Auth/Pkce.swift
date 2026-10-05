import CryptoKit
import Foundation
import Security

/// PKCE (RFC 7636) for the public-client sign-in: S256 challenge, base64url without padding.
enum Pkce {
    /// 64 base64url characters (48 random bytes). Also used for `state` and `nonce`: any unguessable value will do.
    static func verifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        // a predictable verifier would defeat PKCE; the system generator failing means something is badly wrong
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return base64Url(Data(bytes))
    }

    static func challenge(_ verifier: String) -> String {
        base64Url(Data(SHA256.hash(data: Data(verifier.utf8))))
    }
}

/// Base64url without padding (RFC 4648 §5).
func base64Url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// The bytes of base64url `text`, with or without padding; nil when it isn't base64url.
func base64UrlDecoded(_ text: String) -> Data? {
    var base64 = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
    return Data(base64Encoded: base64)
}
