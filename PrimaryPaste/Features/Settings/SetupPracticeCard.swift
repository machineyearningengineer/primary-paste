import AppKit
import SwiftUI

struct SetupPracticeCard: View {
    let disabledReason: String?
    let clipboardLinkMode: ClipboardLinkMode
    let settingsActionTitle: String?
    let openPracticeSettings: () -> Void
    let continueInMenuBar: () -> Void
    @State private var practiceError: String?

    var body: some View {
        SettingsCard {
            SettingsCardHeader(
                title: "Your First Paste",
                detail: "Three small steps. No copying required.",
                systemImage: "cursorarrow.click.2",
                tint: Color.accentColor
            ) { EmptyView() }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) { steps }
                VStack(alignment: .leading, spacing: 14) { steps }
            }

            Divider()
            HStack(spacing: 12) {
                Button("Try It in Your Browser", action: openPracticePage)
                    .buttonStyle(.borderedProminent)
                    .disabled(disabledReason != nil)
                Button("Continue in Menu Bar", action: continueInMenuBar)
                    .help("Close Setup and stop showing it on every launch. Reopen it from the menu bar.")
                Spacer(minLength: 0)
            }
            Text(disabledReason ?? clipboardDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Trackpad? Enable the optional keyboard shortcut in Paste, or map a gesture to middle-click.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let settingsActionTitle {
                Button(settingsActionTitle, action: openPracticeSettings)
                    .buttonStyle(.link)
            }
            if let practiceError {
                Text(practiceError).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var clipboardDetail: String {
        switch clipboardLinkMode {
        case .separate: "Your normal Copy and Paste stay separate. Close this window whenever you’re ready."
        case .importCopies: "Clipboard copies also enter Primary. Close this window whenever you’re ready."
        case .mirrorSelections: "Selections also update your clipboard. Close this window whenever you’re ready."
        }
    }

    @ViewBuilder
    private var steps: some View {
        step(1, title: "Select", detail: "Drag across text in an app.", icon: "selection.pin.in.out")
        step(2, title: "Middle-click", detail: "Click the wheel in a text field.", icon: "computermouse")
        step(3, title: "Keep going", detail: "Your selection appears there.", icon: "checkmark.circle")
    }

    private func step(_ number: Int, title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("\(number). \(title)").font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func openPracticePage() {
        do {
            let directory = try FileManager.default.url(
                for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            ).appendingPathComponent("com.abel.primarypaste/Practice", isDirectory: true)
            let html = Self.practicePage.replacingOccurrences(of: "{{clipboard-detail}}", with: clipboardDetail)
            let page = try PracticePageCache.write(html: html, in: directory)
            practiceError = NSWorkspace.shared.open(page) ? nil : "Could not open your browser. Try again."
        } catch {
            practiceError = "Could not prepare the practice page. Try again."
        }
    }

    static let practicePage = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; form-action 'none'; base-uri 'none'">
          <title>Your First Paste · Primary Paste</title>
          <style>
            :root { color-scheme: light dark; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
            body { margin: 0; color: CanvasText; background: Canvas; }
            main { max-width: 680px; margin: 8vh auto; padding: 32px; }
            .brand { color: #4c9d78; font-weight: 600; letter-spacing: .02em; }
            h1 { font-size: clamp(30px, 5vw, 42px); letter-spacing: -.04em; margin: 16px 0; }
            h2 { font-size: 18px; margin: 0 0 14px; }
            p { line-height: 1.6; }
            .muted { color: color-mix(in srgb, CanvasText 65%, Canvas); }
            section { margin: 24px 0; padding: 24px; border: 1px solid color-mix(in srgb, CanvasText 15%, Canvas); border-radius: 16px; }
            .sample { font-size: 22px; line-height: 1.7; user-select: text; margin-bottom: 0; }
            label { display: block; font-size: 14px; margin-bottom: 10px; }
            textarea { box-sizing: border-box; width: 100%; min-height: 100px; padding: 14px; border-radius: 8px; border: 1px solid color-mix(in srgb, CanvasText 30%, Canvas); font: inherit; color: inherit; background: Canvas; }
            textarea:focus-visible { outline: 3px solid #4c9d78; outline-offset: 3px; }
            a { color: #4c9d78; }
            footer { font-size: 13px; line-height: 1.6; }
          </style>
        </head>
        <body><main>
          <div class="brand">Primary Paste</div>
          <h1>Select. Middle-click. Done.</h1>
          <p class="muted">Keep the text you just selected ready to paste. {{clipboard-detail}}</p>
          <section>
            <h2>1. Drag across this sentence</h2>
            <p class="sample">Meet at 10:30.</p>
          </section>
          <section>
            <h2>2. Middle-click in the field</h2>
            <label for="paste">Press your mouse wheel here. The selected sentence should appear.</label>
            <textarea id="paste" placeholder="Your first paste goes here" spellcheck="false"></textarea>
          </section>
          <p>Using a trackpad? Map a gesture to middle-click in your gesture tool, or enable the keyboard shortcut in Primary Paste → Paste.</p>
          <p class="muted">If nothing appears, check that Primary Paste is enabled and permissions are ready in Setup. Some editors need an app-specific compatibility rule under Apps.</p>
          <footer>Browser links keep their normal middle-click behavior —
            <a href="#native-link" id="native-link">try middle-clicking this link</a> to open a tab.
            This practice page is local and sends nothing anywhere.
          </footer>
        </main></body>
        </html>
        """
}
