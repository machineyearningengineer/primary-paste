# Primary Paste for macOS

**Select text. Middle-click to paste.** A native macOS selection buffer that keeps your ordinary clipboard separate. macOS 14+; Apple Silicon and Intel universal build.

<!-- release-status:start -->
This package template has `private: true` and no app payload. It is not a published installer. The release builder embeds the exact notarized app ZIP, checksum, license and corresponding-source information before publication.
<!-- release-status:end -->

Once a verified package is published:

```sh
npm install --global @machineyearn/primary-paste
primary-paste install
primary-paste doctor
primary-paste start
```

Installing the npm package does not install or launch the app. `install` verifies the bundled offline payload, macOS signature and Gatekeeper acceptance, then copies it to `/Applications`. It refuses to overwrite an existing app and needs a writable Applications folder. Use the original installer for upgrades. There are no install hooks, runtime dependencies or automatic network downloads.

`doctor` is read-only. `start` explicitly opens the installed app; `setup` opens its Setup. The app itself does not need Node.js. Removing this npm package only removes the launcher; quit the app, turn off launch at login and move the app to Trash to remove it.

[Product and setup guide](https://github.com/machineyearningengineer/primary-paste#readme) · [Issues](https://github.com/machineyearningengineer/primary-paste/issues) · GPL-3.0-only. Corresponding source is identified in `SOURCE.txt` and retained with the release.
