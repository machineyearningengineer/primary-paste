import Foundation

struct SetupLaunchPolicy {
    static func shouldOpenSetupWindowOnLaunch(
        showSetupOnLaunch: Bool,
        needsAccessibilitySetup: Bool,
        needsInputMonitoringSetup: Bool,
        needsFinderAutomationSetup: Bool,
        isAppActive: Bool
    ) -> Bool {
        guard isAppActive else { return false }

        return showSetupOnLaunch
            || needsAccessibilitySetup
            || needsInputMonitoringSetup
            || needsFinderAutomationSetup
    }
}
