import AppKit
import ApplicationServices
import Combine
import CoreServices
import Foundation
import IOKit.hidsystem

final class PermissionsCoordinator: ObservableObject {
    private static let finderAutomationRefreshInterval: TimeInterval = 4.0

    @Published private(set) var isAccessibilityTrusted = AXIsProcessTrusted()
    @Published private(set) var isInputMonitoringTrusted = PermissionsCoordinator.checkInputMonitoringAccess()
    @Published private(set) var isFinderAutomationTrusted = false
    var monitorsFinderAutomation = false
    private var refreshTimer: Timer?
    private var isRefreshingFinderAutomation = false
    private var lastFinderAutomationRefreshAt = Date.distantPast

    init(monitorsFinderAutomation: Bool = false) {
        self.monitorsFinderAutomation = monitorsFinderAutomation
        refresh()
    }

    func refresh() {
        refreshFastStatus()
        if monitorsFinderAutomation { refreshFinderAutomationAccess(force: false) }
    }

    func refreshFastStatus() {
        updateIfChanged(&isAccessibilityTrusted, AXIsProcessTrusted())
        updateIfChanged(&isInputMonitoringTrusted, Self.checkInputMonitoringAccess())
    }

    func refreshFinderAutomationStatus() {
        refreshFinderAutomationAccess(force: true)
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        if let refreshTimer {
            RunLoop.main.add(refreshTimer, forMode: .common)
        }
    }

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func requestAccessibilityPermission() {
        let options =
            [
                "AXTrustedCheckOptionPrompt": true
            ] as CFDictionary
        updateIfChanged(&isAccessibilityTrusted, AXIsProcessTrustedWithOptions(options))
    }

    func requestInputMonitoringPermission() {
        let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        updateIfChanged(&isInputMonitoringTrusted, granted || Self.checkInputMonitoringAccess())
        if !isInputMonitoringTrusted {
            openInputMonitoringSettings()
        }
    }

    func requestFinderAutomationPermission() {
        DispatchQueue.global(qos: .userInitiated).async {
            let granted = Self.checkFinderAutomationAccess(askUserIfNeeded: true)
            DispatchQueue.main.async { [weak self] in
                self?.updateFinderAutomationTrust(granted)
            }
        }
    }

    func openAccessibilitySettings() {
        openPrivacyPane(anchor: "Privacy_Accessibility")
    }

    func openInputMonitoringSettings() {
        openPrivacyPane(anchor: "Privacy_ListenEvent")
    }

    func openAutomationSettings() {
        openPrivacyPane(anchor: "Privacy_Automation")
    }

    func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openPrivacyPane(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func updateFinderAutomationTrust(_ isTrusted: Bool) {
        updateIfChanged(&isFinderAutomationTrusted, isTrusted)
    }

    private func refreshFinderAutomationAccess(force: Bool) {
        guard !isRefreshingFinderAutomation else { return }
        if !force, Date().timeIntervalSince(lastFinderAutomationRefreshAt) < Self.finderAutomationRefreshInterval {
            return
        }
        lastFinderAutomationRefreshAt = Date()
        isRefreshingFinderAutomation = true
        DispatchQueue.global(qos: .utility).async {
            let isTrusted = Self.checkFinderAutomationAccess(askUserIfNeeded: false)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                isRefreshingFinderAutomation = false
                updateFinderAutomationTrust(isTrusted)
            }
        }
    }

    private func updateIfChanged(_ value: inout Bool, _ nextValue: Bool) {
        guard value != nextValue else { return }
        value = nextValue
    }

    private static func checkInputMonitoringAccess() -> Bool {
        let hidAccess = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        return hidAccess == kIOHIDAccessTypeGranted || CGPreflightListenEventAccess()
    }

    private static func checkFinderAutomationAccess(askUserIfNeeded: Bool) -> Bool {
        var target = AEAddressDesc()
        let data = Data("com.apple.finder".utf8)
        let createStatus = data.withUnsafeBytes { buffer -> OSStatus in
            guard let baseAddress = buffer.baseAddress else { return OSStatus(errAECoercionFail) }
            return OSStatus(
                AECreateDesc(
                    DescType(typeApplicationBundleID),
                    baseAddress,
                    data.count,
                    &target
                ))
        }
        guard createStatus == noErr else { return false }
        defer { AEDisposeDesc(&target) }

        let status = AEDeterminePermissionToAutomateTarget(
            &target,
            typeWildCard,
            typeWildCard,
            askUserIfNeeded
        )
        return status == noErr
    }
}
