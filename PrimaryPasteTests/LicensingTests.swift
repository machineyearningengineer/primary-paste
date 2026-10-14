import CryptoKit
import XCTest

final class LicensingTests: PrimaryPasteTestCase {
    func testLicenseEnforcementIsExplicitAndOffByDefault() {
        guard let baseURL = URL(string: "https://licensing.example") else {
            return XCTFail("Expected valid test URL")
        }
        let optional = LicenseController(
            configuration: LicensingConfiguration(
                apiBaseURL: baseURL,
                entitlementPublicKey: Data(),
                enforcementEnabled: false
            ),
            keychain: LicenseKeychain(service: "com.abel.primarypaste.tests.\(UUID().uuidString)")
        )
        let required = LicenseController(
            configuration: LicensingConfiguration(
                apiBaseURL: baseURL,
                entitlementPublicKey: Data(),
                enforcementEnabled: true
            ),
            keychain: LicenseKeychain(service: "com.abel.primarypaste.tests.\(UUID().uuidString)")
        )

        XCTAssertTrue(optional.allowsProductUse)
        XCTAssertFalse(required.allowsProductUse)
    }

    func testMalformedEntitlementIsRejected() {
        let verifier = EntitlementVerifier(publicKeyData: Data())
        XCTAssertThrowsError(try verifier.verify("not-a-signed-entitlement", expectedDeviceHash: "device")) { error in
            guard case EntitlementVerificationError.malformedToken = error else {
                return XCTFail("Expected malformed token, got \(error)")
            }
        }
    }
    func testSignedEntitlementsRequireDeviceAudienceAlgorithmAndValidDates() throws {
        let key = P256.Signing.PrivateKey()
        let now = Date(timeIntervalSince1970: 1_000)
        let verifier = EntitlementVerifier(publicKeyData: key.publicKey.x963Representation)
        func token(
            device: String = "device", audience: String = "com.abel.primarypaste", algorithm: String = "ES256",
            refresh: Double = 2_000, expiration: Double = 3_000
        ) throws -> String {
            let header = try JSONSerialization.data(withJSONObject: ["alg": algorithm, "typ": "JWT"])
            let claims: [String: Any] = [
                "iss": "primary-paste-licensing", "aud": audience, "license_id": "license",
                "activation_id": "activation", "device_hash": device, "entitlement": "primary-paste", "iat": 900,
                "refresh_after": refresh, "exp": expiration,
            ]
            let payload = try JSONSerialization.data(withJSONObject: claims)
            func encode(_ data: Data) -> String {
                data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(
                    of: "/", with: "_"
                ).replacingOccurrences(of: "=", with: "")
            }
            let message = "\(encode(header)).\(encode(payload))"
            let signature = try key.signature(for: Data(message.utf8)).rawRepresentation
            return "\(message).\(encode(signature))"
        }
        XCTAssertNoThrow(try verifier.verify(token(), expectedDeviceHash: "device", now: now))
        // Refresh is due, but an unexpired offline entitlement is still valid.
        XCTAssertNoThrow(try verifier.verify(token(refresh: 950), expectedDeviceHash: "device", now: now))
        for invalid in [
            try token(device: "other"), try token(audience: "other"), try token(algorithm: "HS256"),
            try token(expiration: 999), try token(refresh: 4_000),
        ] {
            XCTAssertThrowsError(try verifier.verify(invalid, expectedDeviceHash: "device", now: now))
        }
    }

}
