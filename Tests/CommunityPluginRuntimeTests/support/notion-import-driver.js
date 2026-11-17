/**
 * File: notion-import-driver.js
 * -----------------------------
 * Layer: Tests
 * Description: Walks Obsidian's Importer through a Notion import on the plugin panel, as a person does.
 *
 * Authors: Bahey Shalash
 * Version: 1.0
 * Date: 17/11/2026
 */

// Runs Importer as a person runs it on Graphite's plugin panel: its settings page, the Notion
// format, the file import, the files chosen in the system's picker, then Continue until the import
// starts and its summary shows. The picker is the one thing stood in for: the file input's click
// hands it the chosen files, as WebKit does once a file is picked.
'use strict';

const fileSystem = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { startRuntime, installAndLoadPlugin, plain, settle, waitUntil } = require('./runtime-harness');

const importerFolder = path.join(__dirname, '..', 'compatibility', 'built', 'obsidian-importer');

/// Importer as built (or downloaded from its release) into `compatibility/built`, or null.
function importerPackage() {
    if (!fileSystem.existsSync(path.join(importerFolder, 'main.js'))) return null;
    const read = (name) => (fileSystem.existsSync(path.join(importerFolder, name)) ? fileSystem.readFileSync(path.join(importerFolder, name), 'utf8') : '');
    return { manifest: JSON.parse(read('manifest.json')), mainSource: read('main.js'), styles: read('styles.css') };
}

/// jsdom's `Blob` and `File` have no `arrayBuffer`, `stream` or `slice` reads, and it has no `Response`
/// or streams; WebKit has all of them, and zip.js reads a picked export with them. Node's are used.
function installWebPlatformFiles(window) {
    for (const name of ['Blob', 'File', 'Response', 'Request', 'Headers', 'TransformStream', 'ReadableStream', 'WritableStream',
        'CompressionStream', 'DecompressionStream', 'TextDecoderStream', 'TextEncoderStream']) {
        window[name] = globalThis[name];
    }
}

async function startImporter(files) {
    const harness = await startRuntime({ files: files || { 'Welcome.md': '# Welcome\n' } });
    installWebPlatformFiles(harness.window);
    const answer = plain(await installAndLoadPlugin(harness, importerPackage()));
    await harness.send({ operation: 'plugins.layoutReady' });
    await settle();
    return { harness, answer };
}

/// The next file input clicked gets `archives` (`{ name, bytes }`), as if picked in the system's picker.
function pickFilesOnNextClick(window, archives) {
    const originalClick = window.HTMLInputElement.prototype.click;
    window.HTMLInputElement.prototype.click = function clickWithPickedFiles() {
        if (this.type !== 'file') return originalClick.call(this);
        window.HTMLInputElement.prototype.click = originalClick;
        const files = archives.map((archive) => new window.File([archive.bytes], archive.name, { type: 'application/zip' }));
        Object.defineProperty(this, 'files', { value: files, configurable: true });
        this.dispatchEvent(new window.Event('change'));
        return undefined;
    };
}

function clickSettingNamed(document, name) {
    const row = Array.from(document.querySelectorAll('.setting-item')).find((element) => {
        const nameElement = element.querySelector('.setting-item-name');
        return nameElement && nameElement.textContent === name;
    });
    if (!row) throw new Error('No setting named ' + name + '.');
    row.click();
}

function callToActionButtons(document) {
    return Array.from(document.querySelectorAll('.importer-button-bar button.mod-cta'));
}

function topSettingPage(document) {
    return Array.from(document.querySelectorAll('.setting-page')).at(-1) || null;
}

async function settleMany(count) {
    for (let round = 0; round < count; round += 1) await settle();
}

/// The import's summary as numbers, read from Importer's own counters.
function importSummary(document) {
    const count = (statName) => {
        const element = document.querySelector('.importer-stat.mod-' + statName + ' .importer-stat-count');
        return element ? Number(element.textContent.replace(/[^0-9]/g, '')) : null;
    };
    const page = topSettingPage(document);
    return {
        imported: count('imported'),
        attachments: count('attachments'),
        skipped: count('skipped'),
        failed: count('failed'),
        log: page ? Array.from(page.querySelectorAll('.importer-log .list-item')).map((element) => element.textContent.trim()) : [],
        text: page ? page.textContent : '',
    };
}

/// Imports `archives` with Notion's file import and returns the summary once Importer shows Done.
async function runNotionFileImport(harness, archives) {
    const document = harness.window.document;
    pickFilesOnNextClick(harness.window, archives);
    await harness.send({ operation: 'settings.show', pluginIdentifier: 'obsidian-importer' });
    await settle();
    clickSettingNamed(document, 'Notion');
    await settle();
    clickSettingNamed(document, 'File import');
    await settle();
    const chooser = topSettingPage(document).querySelector('.setting-item.mod-add-item.mod-clickable');
    if (!chooser) throw new Error('Importer showed no way to choose files.');
    chooser.click();
    await settleMany(5);
    // Source, output, then the note template: each has its own Continue before Start import.
    for (let step = 0; step < 8; step += 1) {
        const buttons = callToActionButtons(document);
        if (buttons.some((button) => button.textContent === 'Done')) return importSummary(document);
        if (buttons.length === 0) {
            throw new Error('Importer shows no button to go on: ' + (topSettingPage(document) || document.body).textContent.slice(0, 400));
        }
        buttons[0].click();
        const isDoneShown = () => callToActionButtons(document).some((button) => button.textContent === 'Done');
        await waitUntil(() => !callToActionButtons(document).includes(buttons[0]) || isDoneShown(), 60000).catch(() => {});
        await settleMany(3);
    }
    throw new Error('The import did not finish.');
}

/// Links `secret` under `secretName` with Importer's secret control on its Notion account page, as a
/// person does in its window.
async function linkSecret(harness, secretName, secret) {
    const document = harness.window.document;
    topSettingPage(document).querySelector('button.graphite-secret-link').click();
    await settle();
    const secretWindow = Array.from(document.querySelectorAll('.modal-container .modal')).at(-1);
    const [nameField, secretField] = secretWindow.querySelectorAll('input');
    nameField.value = secretName;
    nameField.dispatchEvent(new harness.window.Event('input'));
    secretField.value = secret;
    secretField.dispatchEvent(new harness.window.Event('input'));
    Array.from(secretWindow.querySelectorAll('button')).find((button) => button.textContent === 'Save and link').click();
}

/// Imports from Notion's API with Importer's Notion account import: the token linked, the pages loaded
/// and all chosen, then Continue until Done. Returns the summary, or `{ stoppedAt }` with the page's text
/// when Importer offers no way on (the pages did not load).
async function runNotionApiImport(harness, secret) {
    const document = harness.window.document;
    await harness.send({ operation: 'settings.show', pluginIdentifier: 'obsidian-importer' });
    await settle();
    clickSettingNamed(document, 'Notion');
    await settle();
    clickSettingNamed(document, 'Notion account (recommended)');
    await settleMany(3);
    await linkSecret(harness, 'notion-token', secret);
    // The page list has loaded once its Load button no longer says Loading.
    const isLoading = () => Array.from(topSettingPage(document).querySelectorAll('button')).some((button) => /Loading/.test(button.textContent));
    await settleMany(2);
    await waitUntil(() => !isLoading(), 60000).catch(() => {});
    await settleMany(3);
    const selectAll = Array.from(topSettingPage(document).querySelectorAll('button')).find((button) => button.textContent === 'Select all');
    if (selectAll) selectAll.click();
    await settleMany(3);
    for (let step = 0; step < 8; step += 1) {
        const buttons = callToActionButtons(document);
        if (buttons.some((button) => button.textContent === 'Done')) return importSummary(document);
        const isDoneShown = () => callToActionButtons(document).some((button) => button.textContent === 'Done');
        // While the import runs, its bar has Pause and Cancel only: wait for it to end, retries and Notion's pauses included.
        if (buttons.length === 0) {
            await waitUntil(isDoneShown, 300000).catch(() => {});
            if (isDoneShown()) continue;
            return { stoppedAt: topSettingPage(document).textContent };
        }
        if (buttons[0].disabled) return { stoppedAt: topSettingPage(document).textContent };
        buttons[0].click();
        await waitUntil(() => !callToActionButtons(document).includes(buttons[0]) || isDoneShown(), 120000).catch(() => {});
        await settleMany(3);
    }
    throw new Error('The import did not finish.');
}

/// Every file under `folder` of the vault: Markdown and other text as text, anything else as its SHA-256.
function vaultSnapshot(harness, folder) {
    const snapshot = {};
    const root = path.join(harness.vaultFolder, folder || '');
    if (!fileSystem.existsSync(root)) return snapshot;
    const visit = (location) => {
        for (const entry of fileSystem.readdirSync(location, { withFileTypes: true }).sort((left, right) => left.name.localeCompare(right.name))) {
            const entryLocation = path.join(location, entry.name);
            const vaultPath = path.relative(harness.vaultFolder, entryLocation).split(path.sep).join('/');
            if (vaultPath.startsWith('.obsidian')) continue;
            if (entry.isDirectory()) visit(entryLocation);
            else if (/\.(md|base|json|txt|csv)$/.test(entry.name)) snapshot[vaultPath] = fileSystem.readFileSync(entryLocation, 'utf8');
            else snapshot[vaultPath] = 'sha256:' + crypto.createHash('sha256').update(fileSystem.readFileSync(entryLocation)).digest('hex');
        }
    };
    visit(root);
    return snapshot;
}

module.exports = { importerPackage, installWebPlatformFiles, startImporter, runNotionFileImport, runNotionApiImport, vaultSnapshot, settleMany, importSummary };
