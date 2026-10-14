import Combine
import CryptoKit
import Foundation

final class LicenseController: ObservableObject {
    @Published private(set) var status: LicenseStatus = .unavailable
    @Published private(set) var lastError: String?
    @Published private(set) var isWorking = false
    private var verifiedExpiration: Date?
    private var refreshTimer: Timer?
    private var nextAutomaticRefresh = Date.distantPast

    let isAvailable: Bool
    private let configuration: LicensingConfiguration?
    private let keychain: LicenseKeychain

    init(configuration: LicensingConfiguration? = .bundled, keychain: LicenseKeychain = LicenseKeychain()) {
        self.configuration = configuration
        self.keychain = keychain
        isAvailable = configuration != nil
        reloadFromKeychain()
        if configuration != nil {
            Task { @MainActor [weak self] in self?.startEntitlementMaintenance() }
        }
    }

    deinit { refreshTimer?.invalidate() }

    @MainActor
    private func startEntitlementMaintenance() {
        maintainEntitlement()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.maintainEntitlement() }
        }
    }

    @MainActor
    private func maintainEntitlement() {
        guard !isWorking else { return }
        reloadFromKeychain()
        guard status == .needsRefresh, Date() >= nextAutomaticRefresh else { return }
        nextAutomaticRefresh = Date().addingTimeInterval(3_600)
        Task { @MainActor [weak self] in await self?.refresh() }
    }

    var allowsProductUse: Bool {
        guard configuration?.enforcementEnabled == true else { return true }
        return verifiedExpiration.map { $0 > Date() } ?? false
    }

    @MainActor
    func beginPurchase() async -> URL? {
        guard let configuration, !isWorking else { return nil }
        isWorking = true
        defer { isWorking = false }
        lastError = nil
        do {
            let installationID = try keychain.loadInstallationID()
            return try await LicensingAPIClient(baseURL: configuration.apiBaseURL)
                .createCheckoutSession(installationID: installationID)
        } catch {
            lastError = "The purchase session could not start."
            return nil
        }
    }

    @MainActor
    func claimPurchase(sessionID: String) async {
        guard let configuration, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        lastError = nil
        do {
            let installationID = try keychain.loadInstallationID()
            let client = LicensingAPIClient(baseURL: configuration.apiBaseURL)
            let key = try await client.claimCheckout(sessionID: sessionID, installationID: installationID)
            try await activateLicense(licenseKey: key, configuration: configuration)
        } catch {
            lastError = "The completed purchase could not be claimed."
        }
    }

    @MainActor
    func activate(licenseKey: String) async throws {
        guard let configuration else { return }
        guard !isWorking else { throw LicensingAPIError.operationInProgress }
        isWorking = true
        defer { isWorking = false }
        lastError = nil
        do {
            try await activateLicense(licenseKey: licenseKey, configuration: configuration)
        } catch {
            lastError = "The license could not be activated. Check the key and your connection, then try again."
            throw error
        }
    }

    @MainActor
    private func activateLicense(licenseKey: String, configuration: LicensingConfiguration) async throws {
        let licenseKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let deviceHash = try makeDeviceHash()
        let response = try await LicensingAPIClient(baseURL: configuration.apiBaseURL)
            .activate(licenseKey: licenseKey, deviceHash: deviceHash)
        _ = try EntitlementVerifier(publicKeyData: configuration.entitlementPublicKey)
            .verify(response.entitlementToken, expectedDeviceHash: deviceHash)
        try keychain.saveLicense(
            StoredLicense(
                licenseKey: licenseKey,
                activationToken: response.activationToken,
                entitlementToken: response.entitlementToken
            )
        )
        lastError = nil
        reloadFromKeychain()
    }

    @MainActor
    func refresh() async {
        guard let configuration, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        lastError = nil
        do {
            guard let stored = try keychain.loadLicense() else {
                if status != .unlicensed { status = .unlicensed }
                return
            }
            let response = try await LicensingAPIClient(baseURL: configuration.apiBaseURL)
                .refresh(activationToken: stored.activationToken)
            _ = try EntitlementVerifier(publicKeyData: configuration.entitlementPublicKey)
                .verify(response.entitlementToken, expectedDeviceHash: try makeDeviceHash())
            let updated = StoredLicense(
                licenseKey: stored.licenseKey,
                activationToken: response.activationToken,
                entitlementToken: response.entitlementToken
            )
            try keychain.saveLicense(updated)
            reloadFromKeychain()
        } catch {
            reloadFromKeychain()
            if case LicensingAPIError.rejected(statusCode: 403) = error {
                try? keychain.removeLicense()
                verifiedExpiration = nil
                status = .revoked
            }
            lastError = "The license could not be refreshed. Try again when your connection is ready."
        }
    }

    @MainActor
    func deactivate() async {
        guard let configuration, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        lastError = nil
        do {
            if let stored = try keychain.loadLicense() {
                try await LicensingAPIClient(baseURL: configuration.apiBaseURL)
                    .deactivate(activationToken: stored.activationToken)
            }
            try keychain.removeLicense()
            verifiedExpiration = nil
            status = .unlicensed
            lastError = nil
        } catch {
            lastError = "The license could not be deactivated."
        }
    }

    private func reloadFromKeychain() {
        verifiedExpiration = nil
        guard let configuration else {
            status = .unavailable
            return
        }
        do {
            guard let stored = try keychain.loadLicense() else {
                if status != .unlicensed { status = .unlicensed }
                return
            }
            let claims = try EntitlementVerifier(publicKeyData: configuration.entitlementPublicKey)
                .verify(stored.entitlementToken, expectedDeviceHash: try makeDeviceHash())
            verifiedExpiration = claims.expiresAt
            let nextStatus: LicenseStatus =
                claims.refreshAfter <= Date() ? .needsRefresh : .active(expiration: claims.expiresAt)
            if status != nextStatus { status = nextStatus }
        } catch {
            if status != .needsRefresh { status = .needsRefresh }
        }
    }

    private func makeDeviceHash() throws -> String {
        let installationID = try keychain.loadInstallationID()
        let digest = SHA256.hash(data: Data("com.abel.primarypaste:\(installationID)".utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
