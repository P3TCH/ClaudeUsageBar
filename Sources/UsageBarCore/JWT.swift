import Foundation

/// Reads the payload of a JWT. The signature is not checked: tokens come
/// straight from the issuer over TLS and are only used to read claims.
public enum JWT {
    public static func payload(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2, let data = Data(base64URLEncoded: String(parts[1])) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    public static func expiry(_ token: String) -> Date? {
        guard let exp = payload(token)?["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
