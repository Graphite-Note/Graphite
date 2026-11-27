/**
 * File: notion-importer-plugin.test.js
 * ------------------------------------
 * Layer: Tests
 * Description: The Notion Importer plugin (the Swift Importer compiled to WebAssembly, Graphite-Note/Importer's
 *              Plugin/) run in the runtime: its settings tab and import window, an import of the made-up Notion
 *              export through the plugin API, a note already in the vault kept, Stop, and a web view without
 *              WebAssembly (Lockdown Mode).
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 27/11/2026
 */
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fileSystem = require('node:fs');
const path = require('node:path');
const { startRuntime, installAndLoadPlugin, waitUntil, plain } = require('../support/runtime-harness');

// Built by the Importer's Plugin/build-plugin.sh and placed beside the other built plugins, which are not committed.
const builtFolder = path.join(__dirname, '..', 'compatibility', 'built', 'graphite-notion-importer');
const isBuilt = fileSystem.existsSync(path.join(builtFolder, 'main.js'));
const smallExport = path.join(__dirname, '..', 'fixtures', 'notion-small-export.zip');

async function harnessWithPlugin(files) {
    const harness = await startRuntime({ files });
    const manifest = JSON.parse(fileSystem.readFileSync(path.join(builtFolder, 'manifest.json'), 'utf8'));
    const answer = await installAndLoadPlugin(harness, {
        manifest,
        mainSource: fileSystem.readFileSync(path.join(builtFolder, 'main.js'), 'utf8'),
        styles: fileSystem.readFileSync(path.join(builtFolder, 'styles.css'), 'utf8'),
    });
    assert.deepEqual(plain(answer), { isLoaded: true });
    return harness;
}

/// Opens the import window from the settings tab, gives its file input `file` and presses Import.
async function startImport(harness, file) {
    const document = harness.window.document;
    await harness.send({ operation: 'settings.show', pluginIdentifier: 'graphite-notion-importer' });
    const importButton = Array.from(document.querySelectorAll('.setting-item button')).find((button) => button.textContent === 'Import…');
    assert.ok(importButton, 'the settings tab has its Import… button');
    importButton.click();
    const input = document.querySelector('.notion-importer input[type=file]');
    assert.ok(input, 'the import window has a file input');
    Object.defineProperty(input, 'files', { value: [file], configurable: true });
    input.dispatchEvent(new harness.window.Event('change'));
    const button = (text) => Array.from(document.querySelectorAll('.notion-importer button')).find((element) => element.textContent === text);
    assert.equal(button('Import').disabled, false);
    button('Import').click();
    return button;
}

function vaultFiles(folder, under) {
    const found = [];
    const walk = (current, relative) => {
        for (const entry of fileSystem.readdirSync(current, { withFileTypes: true })) {
            const entryPath = relative ? relative + '/' + entry.name : entry.name;
            if (entry.isDirectory()) walk(path.join(current, entry.name), entryPath);
            else found.push(entryPath);
        }
    };
    walk(path.join(folder, under), under);
    return found.sort();
}

test('the Notion Importer plugin imports the made-up export into the vault through the plugin API', { skip: !isBuilt && 'not built' }, async () => {
    const harness = await harnessWithPlugin({ 'Notion/Welcome.md': 'mine\n' });
    try {
        const file = new File([fileSystem.readFileSync(smallExport)], 'Export-study-notes.zip', { type: 'application/zip' });
        const button = await startImport(harness, file);
        await waitUntil(() => button('Open the report') !== undefined
            || /failed/.test(harness.window.document.querySelector('.notion-importer-status').textContent), 60000);
        const status = harness.window.document.querySelector('.notion-importer-status').textContent;
        assert.match(status, /^Imported \d+ notes, \d+ bases and 2 attachments in /, status);
        const summary = plain(harness.app.plugins.plugins['graphite-notion-importer'].lastSummary);
        assert.equal(summary.failed, 0);
        assert.equal(summary.wasCancelled, false);
        assert.equal(summary.attachments, 2);
        const files = vaultFiles(harness.vaultFolder, 'Notion');
        assert.ok(files.includes('Notion/Notion import report.md'), files.join('\n'));
        assert.equal(files.filter((name) => name.endsWith('.md')).length, summary.notes + 2, 'the notes, the report and Welcome.md');
        assert.equal(harness.readVaultFile('Notion/Welcome.md'), 'mine\n', 'a note already in the vault is kept');
        assert.match(harness.readVaultFile('Notion/Notion import report.md'), /^# Notion import\n/);
        const problems = harness.consoleMessages.filter((message) => message.level === 'error');
        assert.deepEqual(problems, []);
    } finally {
        harness.close();
    }
});

test('Stop ends the import at the next page with its report, and nothing it wrote is half written', { skip: !isBuilt && 'not built' }, async () => {
    const harness = await harnessWithPlugin({});
    try {
        const file = new File([fileSystem.readFileSync(smallExport)], 'Export-study-notes.zip', { type: 'application/zip' });
        const button = await startImport(harness, file);
        button('Stop').click();
        await waitUntil(() => button('Open the report') !== undefined, 60000);
        const summary = plain(harness.app.plugins.plugins['graphite-notion-importer'].lastSummary);
        assert.equal(summary.wasCancelled, true);
        assert.match(harness.readVaultFile(summary.reportPath), /stopped before its end/);
    } finally {
        harness.close();
    }
});

test('without WebAssembly, as in WebKit in Lockdown Mode, the plugin says so and imports nothing', { skip: !isBuilt && 'not built' }, async () => {
    const harness = await harnessWithPlugin({});
    try {
        const window = harness.window;
        window.eval('delete globalThis.WebAssembly');
        assert.equal(window.eval('typeof WebAssembly'), 'undefined');
        await harness.send({ operation: 'settings.show', pluginIdentifier: 'graphite-notion-importer' });
        const notice = window.document.querySelector('.notion-importer-unavailable');
        assert.ok(notice, 'the settings tab says WebAssembly is off');
        assert.match(notice.textContent, /needs WebAssembly.*Lockdown Mode.*Import › From Notion/s);
        Array.from(window.document.querySelectorAll('.setting-item button')).find((button) => button.textContent === 'Import…').click();
        const status = window.document.querySelector('.notion-importer-status');
        assert.match(status.textContent, /needs WebAssembly.*Lockdown Mode/s);
        assert.ok(status.classList.contains('mod-warning'));
        const input = window.document.querySelector('.notion-importer input[type=file]');
        assert.equal(input.disabled, true);
        const file = new File([fileSystem.readFileSync(smallExport)], 'Export-study-notes.zip', { type: 'application/zip' });
        Object.defineProperty(input, 'files', { value: [file], configurable: true });
        input.dispatchEvent(new window.Event('change'));
        const importButton = Array.from(window.document.querySelectorAll('.notion-importer button')).find((button) => button.textContent === 'Import');
        assert.equal(importButton.disabled, true, 'Import stays off with a file picked');
        importButton.click();
        assert.equal(fileSystem.existsSync(path.join(harness.vaultFolder, 'Notion')), false, 'nothing is written');
        assert.deepEqual(harness.consoleMessages.filter((message) => message.level === 'error'), []);
    } finally {
        harness.close();
    }
});
