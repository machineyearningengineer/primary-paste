// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Abel
import Foundation

let appURL = URL(fileURLWithPath: "/Applications/Primary Paste.app")
let ownURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let enclosingApp = ownURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let infoURL = enclosingApp.appendingPathComponent("Contents/Info.plist")
let info = NSDictionary(contentsOf: infoURL)
let version = info?["CFBundleShortVersionString"] as? String ?? "__RELEASE_VERSION__"
let command = CommandLine.arguments.dropFirst().first ?? "help"

func output(_ value: String, failure: Bool = false) {
    let data = Data((value + "\n").utf8)
    (failure ? FileHandle.standardError : FileHandle.standardOutput).write(data)
}

func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    if process.terminationStatus != 0 { exit(process.terminationStatus) }
}

do {
    guard CommandLine.arguments.count <= 2 else {
        output("Commands take no extra arguments. Use primary-paste help.", failure: true)
        exit(2)
    }
    switch command {
    case "help", "--help", "-h":
        output(
            """
            Primary Paste — select text, middle-click to paste, keep your clipboard.
            Usage: primary-paste <help|version|doctor|start|setup>
              doctor  Check the installed app without opening it or requesting permissions
              start   Explicitly open the installed app
              setup   Explicitly open Setup in the installed app
            This helper uses /Applications/Primary Paste.app. Install the app first.
            """)
    case "version", "--version", "-v":
        output(version)
    case "doctor", "start", "setup":
        let installedInfo = NSDictionary(contentsOf: appURL.appendingPathComponent("Contents/Info.plist"))
        guard installedInfo?["CFBundleIdentifier"] as? String == "com.abel.primarypaste" else {
            output("Install Primary Paste.app in /Applications before using this command.", failure: true)
            exit(1)
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path])
        if command == "doctor" {
            output("Installed: \(appURL.path)")
            output("Version: \(installedInfo?["CFBundleShortVersionString"] ?? "unknown")")
            output("Signature integrity passed. Open Setup to check permissions and service status.")
            output("This does not prove Developer ID trust or real-app compatibility.")
        } else if command == "start" {
            try run("/usr/bin/open", [appURL.path])
        } else {
            try run("/usr/bin/open", ["-a", appURL.path, "primarypaste://show-setup"])
        }
    default:
        output("Unknown command: \(command). Use primary-paste help.", failure: true)
        exit(2)
    }
} catch {
    output("Primary Paste: \(error.localizedDescription)", failure: true)
    exit(1)
}
