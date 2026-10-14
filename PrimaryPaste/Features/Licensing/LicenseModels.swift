import Foundation

enum LicenseStatus: Equatable {
    case unavailable
    case unlicensed
    case active(expiration: Date)
    case needsRefresh
    case revoked
}

struct LicenseEntitlement: Codable, Equatable {
    let issuer: String
    let audience: String
    let licenseID: String
    let activationID: String
    let deviceHash: String
    let entitlement: String
    let issuedAt: Date
    let refreshAfter: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case issuer = "iss"
        case audience = "aud"
        case licenseID = "license_id"
        case activationID = "activation_id"
        case deviceHash = "device_hash"
        case entitlement
        case issuedAt = "iat"
        case refreshAfter = "refresh_after"
        case expiresAt = "exp"
    }
}

struct StoredLicense: Codable, Equatable {
    let licenseKey: String
    let activationToken: String
    let entitlementToken: String
}

struct CheckoutSessionResponse: Decodable {
    let checkoutURL: URL
}

struct CheckoutClaimResponse: Decodable {
    let licenseKey: String
}

struct ActivationResponse: Decodable {
    let activationToken: String
    let entitlementToken: String
}
