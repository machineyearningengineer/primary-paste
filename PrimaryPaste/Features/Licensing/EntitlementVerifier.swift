import CryptoKit
import Foundation

enum EntitlementVerificationError: Error {
    case malformedToken
    case invalidSignature
    case invalidClaims
}

struct EntitlementVerifier {
    let publicKeyData: Data

    func verify(_ token: String, expectedDeviceHash: String, now: Date = Date()) throws -> LicenseEntitlement {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
            let headerData = Data(base64URLEncoded: String(parts[0])),
            let payload = Data(base64URLEncoded: String(parts[1])),
            let signatureData = Data(base64URLEncoded: String(parts[2]))
        else {
            throw EntitlementVerificationError.malformedToken
        }

        struct Header: Decodable {
            let alg: String
            let typ: String
        }
        guard let header = try? JSONDecoder().decode(Header.self, from: headerData),
            header.alg == "ES256", header.typ == "JWT"
        else {
            throw EntitlementVerificationError.malformedToken
        }

        let signedBytes = Data("\(parts[0]).\(parts[1])".utf8)
        let publicKey = try P256.Signing.PublicKey(x963Representation: publicKeyData)
        let signature = try P256.Signing.ECDSASignature(rawRepresentation: signatureData)
        guard publicKey.isValidSignature(signature, for: signedBytes) else {
            throw EntitlementVerificationError.invalidSignature
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let claims = try decoder.decode(LicenseEntitlement.self, from: payload)
        guard claims.issuer == "primary-paste-licensing",
            claims.audience == "com.abel.primarypaste",
            claims.deviceHash == expectedDeviceHash,
            claims.entitlement == "primary-paste",
            claims.issuedAt <= now.addingTimeInterval(300),
            claims.expiresAt > now,
            claims.issuedAt < claims.refreshAfter,
            claims.refreshAfter < claims.expiresAt,
            !claims.licenseID.isEmpty, !claims.activationID.isEmpty
        else {
            throw EntitlementVerificationError.invalidClaims
        }
        return claims
    }
}

extension Data {
    fileprivate init?(base64URLEncoded value: String) {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
