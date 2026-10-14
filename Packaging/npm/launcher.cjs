#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');

const appPath = '/Applications/Primary Paste.app';
const help = `Primary Paste — select text, middle-click to paste, keep your clipboard.

Usage: primary-paste <command>
  install   Install the bundled verified app; never overwrites an existing app
  doctor    Check the installed app without launching or requesting permissions
  start     Open the installed app
  setup     Open Setup in the installed app
  version   Print this package's version
  help      Show this guide

macOS 14+ only. No automatic downloads, app launch or permission changes.
Uninstall the launcher with npm; remove the app separately after quitting it.
`;

function run(file, args, runner = spawnSync) {
  const result = runner(file, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  if (result.error || result.status !== 0) {
    throw new Error(`${path.basename(file)} failed: ${(result.stderr || result.error?.message || `exit ${result.status}`).trim()}`);
  }
  return result.stdout.trim();
}

function readRelease(root) {
  const manifestPath = path.join(root, 'release.json');
  if (!fs.existsSync(manifestPath)) throw new Error('This is a source template, not a packaged release. Use Docs/Developing.md.');
  const release = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
  if (release.schema !== 1 || release.version !== pkg.version || release.bundleID !== 'com.abel.primarypaste') {
    throw new Error('Release metadata does not match this package.');
  }
  if (!release.notarized || !release.developerID || pkg.private !== false) {
    throw new Error('This payload is an unsigned/private preview and cannot be installed through this launcher.');
  }
  if (!/^[a-f0-9]{64}$/.test(release.zipSHA256) || release.zipFile !== 'Primary-Paste.zip') {
    throw new Error('Invalid payload name or checksum.');
  }
  return release;
}

function verifyArchive(root, release) {
  const archive = path.join(root, 'payload', release.zipFile);
  const actual = crypto.createHash('sha256').update(fs.readFileSync(archive)).digest('hex');
  if (actual !== release.zipSHA256) throw new Error('Bundled app checksum failed. Nothing was installed.');
  return archive;
}

function install(root, runner = spawnSync) {
  const release = readRelease(root);
  const archive = verifyArchive(root, release);
  if (fs.existsSync(appPath)) throw new Error('Primary Paste is already installed. Use its original installation route to upgrade.');
  fs.accessSync('/Applications', fs.constants.W_OK);
  // Extraction is disposable; the final rename stays on the Applications filesystem.
  const extraction = fs.mkdtempSync(path.join(os.tmpdir(), 'primary-paste-extract-'));
  let stage;
  try {
    run('/usr/bin/ditto', ['-x', '-k', archive, extraction], runner);
    const source = path.join(extraction, 'Primary Paste.app');
    run('/usr/bin/codesign', ['--verify', '--deep', '--strict', source], runner);
    run('/usr/sbin/spctl', ['--assess', '--type', 'execute', source], runner);
    const bundle = run('/usr/libexec/PlistBuddy', ['-c', 'Print :CFBundleIdentifier', path.join(source, 'Contents/Info.plist')], runner);
    const version = run('/usr/libexec/PlistBuddy', ['-c', 'Print :CFBundleShortVersionString', path.join(source, 'Contents/Info.plist')], runner);
    if (bundle !== release.bundleID || version !== release.version) throw new Error('Extracted app identity/version does not match the package.');
    stage = fs.mkdtempSync('/Applications/.primary-paste-install-');
    const stagedApp = path.join(stage, 'Primary Paste.app');
    run('/usr/bin/ditto', [source, stagedApp], runner);
    run('/usr/bin/codesign', ['--verify', '--deep', '--strict', stagedApp], runner);
    // Reserve the destination without replacement: rename cannot destroy an existing app.
    fs.mkdirSync(appPath);
    try {
      fs.renameSync(stagedApp, appPath);
    } catch (error) {
      fs.rmdirSync(appPath); // Only our still-empty reservation; never recursively remove an app.
      throw error;
    }
    return `Installed ${appPath}. Run primary-paste start when ready to grant permissions.`;
  } finally {
    fs.rmSync(extraction, { recursive: true, force: true });
    if (stage) fs.rmSync(stage, { recursive: true, force: true });
  }
}

function main(args, root = __dirname, platform = process.platform, runner = spawnSync) {
  const command = args[0] || 'help';
  if (args.length > 1) throw new Error('This command takes no additional arguments. Run primary-paste help.');
  if (['help', '--help', '-h'].includes(command)) return help;
  if (['version', '--version', '-v'].includes(command)) {
    return JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8')).version;
  }
  if (!['install', 'doctor', 'start', 'setup'].includes(command)) throw new Error(`Unknown command: ${command}. Run primary-paste help.`);
  if (platform !== 'darwin') throw new Error('Primary Paste requires macOS 14 or later. No software was installed or launched.');
  const major = Number(run('/usr/bin/sw_vers', ['-productVersion'], runner).split('.')[0]);
  if (!Number.isInteger(major) || major < 14) throw new Error('Primary Paste requires macOS 14 or later.');
  if (command === 'install') return install(root, runner);
  if (!fs.existsSync(appPath)) throw new Error('Primary Paste.app is not installed in /Applications. Use primary-paste install or the original app installer.');
  const cli = path.join(appPath, 'Contents/MacOS/primary-paste');
  // Never execute an arbitrary existing app's helper before verifying its identity.
  run('/usr/bin/codesign', ['--verify', '--deep', '--strict', appPath], runner);
  const bundle = run('/usr/libexec/PlistBuddy', ['-c', 'Print :CFBundleIdentifier', path.join(appPath, 'Contents/Info.plist')], runner);
  if (bundle !== 'com.abel.primarypaste') throw new Error('Unexpected installed app identity.');
  if (!fs.existsSync(cli)) throw new Error('This development app predates the release CLI. Use its menu bar and Setup directly.');
  return run(cli, [command], runner);
}

module.exports = { main, readRelease, verifyArchive, run };
if (require.main === module) {
  try { process.stdout.write(`${main(process.argv.slice(2))}\n`); }
  catch (error) { process.stderr.write(`Primary Paste: ${error.message}\n`); process.exitCode = 1; }
}
