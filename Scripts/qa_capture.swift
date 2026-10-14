import AppKit
import CoreGraphics
import Foundation

// Guest-only, named-window capture. No host screen, clipboard or input access.
var virtualMachine: Int32 = 0
var valueSize = MemoryLayout<Int32>.size
let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
    "Library/Application Support/Primary Paste QA Guest")
let ownership = try? Data(contentsOf: root.appendingPathComponent("ownership.json"))
let record = ownership.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
func stop(_ message: String) -> Never {
    fputs(message + "\n", stderr)
    exit(1)
}
guard sysctlbyname("kern.hv_vmm_present", &virtualMachine, &valueSize, nil, 0) == 0,
    virtualMachine == 1, record?["owner"] as? String == "primary-paste-qa-guest"
else { stop("Capture is restricted to the owned disposable guest.") }
let arguments = CommandLine.arguments
guard arguments.count >= 2 else { stop("Use permission, window BUNDLE filename.png or video filename.mov duration.") }
if arguments[1] == "permission" {
    print("Guest capture permission:", CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess())
    exit(0)
}
guard CGPreflightScreenCaptureAccess() else { stop("Guest capture permission is required; use permission first.") }
let screens = root.appendingPathComponent("Screens")
if (try? screens.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
    stop("Screens must not be a symbolic link.")
}
try FileManager.default.createDirectory(at: screens, withIntermediateDirectories: true)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
if arguments[1] == "window", arguments.count == 4 {
    let bundles = ["com.abel.primarypaste", "com.apple.Safari", "com.apple.TextEdit"]
    guard bundles.contains(arguments[2]),
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: arguments[2]).first,
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]],
        let window = windows.first(where: {
            $0[kCGWindowOwnerPID as String] as? pid_t == app.processIdentifier
                && ($0[kCGWindowName as String] as? String ?? "").contains("Primary Paste")
                && $0[kCGWindowLayer as String] as? Int == 0
        }), let identifier = window[kCGWindowNumber as String] as? UInt32
    else { stop("A named, visible test window is required.") }
    guard arguments[3].range(of: "^[a-zA-Z0-9_-]+\\.png$", options: .regularExpression) != nil
    else { stop("Use a plain PNG filename.") }
    process.arguments = ["-x", "-o", "-l", String(identifier), screens.appendingPathComponent(arguments[3]).path]
} else if arguments[1] == "video", arguments.count == 4 {
    guard arguments[2].range(of: "^[a-zA-Z0-9_-]+\\.mov$", options: .regularExpression) != nil,
        let duration = Int(arguments[3]), (1...30).contains(duration)
    else { stop("Use a plain MOV filename and 1–30 seconds.") }
    process.arguments = [
        "-x", "-C", "-k", "-v", "-V", String(duration), "-R0,24,1280,752",
        screens.appendingPathComponent(arguments[2]).path,
    ]
} else {
    stop("Unknown capture command.")
}
if let output = process.arguments?.last,
    (try? URL(fileURLWithPath: output).resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
{
    stop("Capture must not replace a symbolic link.")
}
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { stop("Native guest capture failed.") }
print("Guest capture saved in the owned Screens folder.")
