'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { main, readRelease, verifyArchive, run } = require('../launcher.cjs');

function fixture(t, changes = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'primary-paste-package-test-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  fs.mkdirSync(path.join(root, 'payload'));
  fs.writeFileSync(path.join(root, 'payload/Primary-Paste.zip'), 'synthetic archive');
  fs.writeFileSync(path.join(root, 'package.json'), JSON.stringify({ version: '0.1.0', private: false }));
  const release = {
    schema: 1, version: '0.1.0', bundleID: 'com.abel.primarypaste',
    notarized: true, developerID: true, zipFile: 'Primary-Paste.zip',
    zipSHA256: crypto.createHash('sha256').update('synthetic archive').digest('hex'), ...changes,
  };
  fs.writeFileSync(path.join(root, 'release.json'), JSON.stringify(release));
  return root;
}

test('help and version never execute, fetch, install or require macOS', () => {
  const noRun = () => { throw new Error('Unexpected external operation'); };
  assert.match(main([], path.join(__dirname, '..'), 'linux', noRun), /Usage:/);
  assert.match(main(['help'], path.join(__dirname, '..'), 'darwin', noRun), /No automatic downloads/);
  assert.equal(main(['version'], path.join(__dirname, '..'), 'linux', noRun), require('../package.json').version);
});
test('unknown commands and extra arguments fail before any operation', () => {
  const noRun = () => { throw new Error('Unexpected operation'); };
  assert.throws(() => main(['uninstall'], __dirname, 'darwin', noRun), /Unknown command/);
  assert.throws(() => main(['install', '--force'], __dirname, 'darwin', noRun), /no additional arguments/);
});
test('unsupported platforms reject install without external operations', () => {
  assert.throws(() => main(['install'], __dirname, 'linux', () => { throw Error('unexpected'); }), /requires macOS/);
});
test('old macOS rejects before filesystem mutation', () => {
  assert.throws(() => main(['install'], __dirname, 'darwin', () => ({ status: 0, stdout: '13.7', stderr: '' })), /requires macOS/);
});
test('source templates fail with an actionable error', () => {
  assert.throws(() => readRelease(path.join(__dirname, '..')), /source template/);
});
test('unsigned, mismatched and unsafe payload metadata cannot install', t => {
  for (const changes of [{ notarized: false }, { developerID: false }, { version: '0.2.0' },
    { bundleID: 'other.app' }, { zipFile: '../other.zip' }, { zipSHA256: 'invalid' }]) {
    const root = fixture(t, changes);
    assert.throws(() => readRelease(root));
  }
});
test('private preview remains blocked even with release-like flags', t => {
  const root = fixture(t);
  fs.writeFileSync(path.join(root, 'package.json'), JSON.stringify({ version: '0.1.0', private: true }));
  assert.throws(() => readRelease(root), /unsigned\/private preview/);
});
test('verified archive hash detects tampering before extraction', t => {
  const root = fixture(t);
  const release = readRelease(root);
  assert.equal(verifyArchive(root, release), path.join(root, 'payload/Primary-Paste.zip'));
  fs.appendFileSync(path.join(root, 'payload/Primary-Paste.zip'), 'tampered');
  assert.throws(() => verifyArchive(root, release), /checksum failed/);
});
test('spawn errors and nonzero exits are not reported as success', () => {
  assert.throws(() => run('/usr/bin/example', [], () => ({ error: Error('not found') })), /not found/);
  assert.throws(() => run('/usr/bin/example', [], () => ({ status: 1, stderr: 'trust rejected' })), /trust rejected/);
});
