import AppKit
import SwiftUI

struct LicensingSettingsView: View {
    @ObservedObject var licensing: LicenseController
    @State private var licenseKey = ""

    var body: some View {
        SettingsPage(title: "License", subtitle: "Purchase, activate, or manage this installation.") {
            SettingsCard {
                Text(statusText)
                if let lastError = licensing.lastError {
                    Text(lastError).foregroundStyle(.red)
                }
                TextField("License key", text: $licenseKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Activate") {
                        let key = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !key.isEmpty else { return }
                        Task {
                            do {
                                try await licensing.activate(licenseKey: key)
                                licenseKey = ""
                            } catch { /* The controller presents a recovery message. */  }
                        }
                    }
                    .disabled(licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("Buy License") {
                        Task {
                            guard let url = await licensing.beginPurchase() else { return }
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Refresh") { Task { await licensing.refresh() } }
                    Button("Deactivate", role: .destructive) { Task { await licensing.deactivate() } }
                }
                .disabled(licensing.isWorking)
                if licensing.isWorking { ProgressView("Updating license…").controlSize(.small) }
            }
        }
    }

    private var statusText: String {
        switch licensing.status {
        case .unavailable: "Licensing is not enabled in this build."
        case .unlicensed: "No license is active."
        case .active(let expiration): "License active until \(expiration.formatted())."
        case .needsRefresh: "The license needs an online refresh."
        case .revoked: "The license was revoked."
        }
    }
}
