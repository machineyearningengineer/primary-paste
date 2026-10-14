import Foundation

struct LicensingConfiguration: Equatable {
    let apiBaseURL: URL
    let entitlementPublicKey: Data
    let enforcementEnabled: Bool

    static var bundled: LicensingConfiguration? {
        guard Bundle.main.object(forInfoDictionaryKey: "LicensingEnabled") as? Bool == true,
            let baseURLString = Bundle.main.object(forInfoDictionaryKey: "LicensingAPIBaseURL") as? String,
            let baseURL = URL(string: baseURLString),
            baseURL.scheme == "https",
            let publicKeyString = Bundle.main.object(forInfoDictionaryKey: "LicensingPublicKey") as? String,
            let publicKey = Data(base64Encoded: publicKeyString), publicKey.count == 65
        else {
            return nil
        }

        return LicensingConfiguration(
            apiBaseURL: baseURL,
            entitlementPublicKey: publicKey,
            enforcementEnabled: Bundle.main.object(forInfoDictionaryKey: "LicensingEnforcementEnabled") as? Bool == true
        )
    }
}
