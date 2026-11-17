/**
 * File: importer-runtime-gaps.test.js
 * -----------------------------------
 * Layer: Tests
 * Description: The runtime gaps running Obsidian's Importer found, each fixed for every plugin.
 *
 * Authors: Bahey Shalash
 * Version: 1.0
 * Date: 17/11/2026
 */

// Running Obsidian's own Importer on Notion's export and API (notion-import.test.js) found six gaps of
// the runtime, fixed for every plugin: Obsidian's `htmlToMarkdown`, which every importer writes its notes
// with; `DataWriteOptions` times on writes; the settings window's structure, which Importer puts its step
// buttons in; Obsidian 1.11's `SecretComponent(app, element)`, which links a keychain secret by its name;
// `metadataTypeManager.getAssignedWidget`; and `generateMarkdownLink`, which gives a link, never an embed.
// Each is checked here with a plain plugin or the API itself, without Importer.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fileSystem = require('node:fs');
const path = require('node:path');
const { startRuntime, installAndLoadPlugin, plain } = require('../support/runtime-harness');

const manifest = { id: 'example', name: 'Example', version: '1.0.0', minAppVersion: '1.0.0' };

test('htmlToMarkdown writes Markdown as Obsidian\'s does, with Turndown on the page as window.TurndownService', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const { htmlToMarkdown } = harness.obsidian;
        assert.equal(typeof harness.window.TurndownService, 'function', 'Obsidian gives plugins Turndown itself');
        // Obsidian escapes no Markdown punctuation, so a callout's marker stays a callout.
        assert.equal(htmlToMarkdown('<blockquote>[!important] Read *this*</blockquote>'), '> [!important] Read *this*');
        assert.equal(htmlToMarkdown('<p><strong>bold</strong>, <em>italic</em>, <del>struck</del>, <mark>marked</mark></p>'),
            '**bold**, _italic_, ~~struck~~, ==marked==');
        // One space after a list marker, items' own lines indented by four.
        assert.equal(htmlToMarkdown('<ul><li>One<ul><li>Two</li></ul></li></ul><ol start="3"><li>Three</li><li>Four</li></ol>'),
            '- One\n    - Two\n\n3. Three\n4. Four');
        assert.equal(htmlToMarkdown('<h2>Heading</h2><pre><code class="language-python">print(1)</code></pre><hr>'),
            '## Heading\n\n```python\nprint(1)\n```\n\n---');
        assert.equal(htmlToMarkdown('<a href="Some Note.md">a link</a> <img src="my image.png" alt="a picture">'),
            '[a link](Some%20Note.md) ![a picture](my%20image.png)');
        // Tables come unpadded, an empty header row made up when the table has none, and an empty table gives nothing.
        assert.equal(htmlToMarkdown('<table><tr><td>a</td><td>b|c</td></tr><tr><td>d</td></tr></table>'), '|   |   |\n|---|---|\n|a|b\\|c|\n|d|');
        assert.equal(htmlToMarkdown('<table><thead><tr><th>Name</th><th>Size</th></tr></thead><tbody><tr><td>x</td><td>1</td></tr></tbody></table>'),
            '|Name|Size|\n|---|---|\n|x|1|');
        assert.equal(htmlToMarkdown('<table></table>'), '');
        assert.equal(htmlToMarkdown('<html><head><title>Title</title><style>p {}</style></head><body><p>Body</p><script>x()</script></body></html>'), 'Body');
        // A document, an element and a fragment are taken as well as text.
        const element = harness.window.document.createElement('div');
        element.innerHTML = '<p>From an element</p>';
        assert.equal(htmlToMarkdown(element), 'From an element');
        const fragment = harness.window.document.createRange().createContextualFragment('<p>From</p><p>a fragment</p>');
        assert.equal(htmlToMarkdown(fragment), 'From\n\na fragment');
    } finally {
        harness.close();
    }
});

test('a write\'s DataWriteOptions times are the file\'s times, on create, modify and process', async () => {
    const harness = await startRuntime({ files: { 'Existing.md': 'Before\n' } });
    try {
        const vault = harness.app.vault;
        const created = await vault.create('Imported.md', 'Imported\n', { ctime: Date.UTC(2026, 8, 1, 8), mtime: Date.UTC(2026, 9, 1, 9, 15) });
        assert.equal(created.stat.mtime, Date.UTC(2026, 9, 1, 9, 15), 'the runtime\'s file has the time');
        assert.equal(fileSystem.statSync(path.join(harness.vaultFolder, 'Imported.md')).mtimeMs, Date.UTC(2026, 9, 1, 9, 15), 'and so has the file on disk');
        const existing = vault.getAbstractFileByPath('Existing.md');
        await vault.modify(existing, 'After\n', { mtime: Date.UTC(2025, 0, 2) });
        assert.equal(existing.stat.mtime, Date.UTC(2025, 0, 2));
        await vault.process(existing, (text) => text + 'More\n', { mtime: Date.UTC(2025, 0, 3) });
        assert.equal(existing.stat.mtime, Date.UTC(2025, 0, 3));
        const binary = await vault.createBinary('picture.png', new Uint8Array([1, 2, 3]).buffer, { mtime: Date.UTC(2025, 0, 4) });
        assert.equal(binary.stat.mtime, Date.UTC(2025, 0, 4));
        const plainWrite = await vault.create('Now.md', 'Now\n');
        assert.ok(plainWrite.stat.mtime > Date.UTC(2026, 0, 1), 'a write without times is dated now');
        assert.deepEqual(plain(harness.host.notificationsOf('plugin.unsupportedFeature')), []);
    } finally {
        harness.close();
    }
});

test('a setting tab and its pages show inside Obsidian\'s settings window, where plugins keep what stays outside a page', async () => {
    // Importer keeps its step buttons in `.vertical-tab-content-container`, outside the scrolling page,
    // and styles them as `.modal.mod-settings .importer-button-bar`.
    const source = `"use strict";
var obsidian = require("obsidian");
class StepPage extends obsidian.SettingPage { display() { this.containerEl.empty(); this.containerEl.createDiv({ text: 'Step one' }); } }
class ExampleTab extends obsidian.PluginSettingTab {
    display() {
        this.containerEl.empty();
        const pane = this.containerEl.ownerDocument.querySelector('.vertical-tab-content-container');
        this.plugin.barElement = pane ? pane.createDiv('example-button-bar') : null;
        new obsidian.Setting(this.containerEl).setName('Start').setNavigable(() => {
            const page = new StepPage(); page.title = 'Step'; this.app.setting.openPage(page);
        });
    }
    hide() { if (this.plugin.barElement) this.plugin.barElement.detach(); }
}
class ExamplePlugin extends obsidian.Plugin { onload() { this.addSettingTab(new ExampleTab(this.app, this)); } }
module.exports = ExamplePlugin;`;
    const harness = await startRuntime({ files: {} });
    try {
        assert.deepEqual(plain(await installAndLoadPlugin(harness, { manifest, mainSource: source })), { isLoaded: true });
        await harness.send({ operation: 'settings.show', pluginIdentifier: 'example' });
        const document = harness.window.document;
        const container = document.querySelector('.graphite-plugin-surface > .modal.mod-settings > .vertical-tab-content-container');
        assert.ok(container, 'the settings window is there');
        assert.ok(container.querySelector(':scope > .vertical-tab-content .setting-item'), 'the tab is inside it');
        assert.ok(container.querySelector(':scope > .example-button-bar'), 'what the plugin put beside the tab stays');
        document.querySelector('.setting-item.mod-navigable').click();
        assert.equal(document.querySelector('.setting-page').parentElement, container, 'a page opens beside its tab, as in Obsidian');
        harness.runtime.pluginSurface.handleClosedByPerson();
        assert.equal(document.querySelector('.mod-settings'), null, 'closing the panel takes the window away');
        assert.equal(document.querySelector('.example-button-bar'), null);
    } finally {
        harness.close();
    }
});

test('SecretComponent links a secret by its name: chosen from the vault\'s secrets, or made new in its window', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const { SecretComponent, Setting } = harness.obsidian;
        const document = harness.window.document;
        const element = document.body.createDiv();
        const chosenNames = [];
        const component = new SecretComponent(harness.app, element).onChange((secretName) => chosenNames.push(secretName));
        assert.equal(element.querySelector('button').textContent, 'Link…');
        element.querySelector('button').click();
        const window = document.querySelector('.modal-container .modal');
        assert.equal(window.querySelector('.modal-title').textContent, 'Link a secret');
        const [nameField, secretField] = window.querySelectorAll('input');
        assert.equal(secretField.type, 'password', 'the secret is not shown as it is typed');
        nameField.value = 'notion-token';
        nameField.dispatchEvent(new harness.window.Event('input'));
        secretField.value = 'ntn_made_up';
        secretField.dispatchEvent(new harness.window.Event('input'));
        Array.from(window.querySelectorAll('button')).find((button) => button.textContent === 'Save and link').click();
        assert.deepEqual(chosenNames, ['notion-token'], 'the plugin gets the name, never the secret');
        assert.equal(harness.app.secretStorage.getSecret('notion-token'), 'ntn_made_up');
        assert.equal(component.getValue(), 'notion-token');
        assert.equal(element.querySelector('button').textContent, 'notion-token');
        const keptSecrets = plain(harness.host.notificationsOf('secrets.set'));
        const expectedSecret = { operation: 'secrets.set', secretIdentifier: 'notion-token', secret: 'ntn_made_up' };
        assert.deepEqual(keptSecrets, [expectedSecret], 'Graphite keeps it in the keychain');
        // Linked again later, from the list.
        element.querySelector('button').click();
        const secondWindow = Array.from(document.querySelectorAll('.modal-container .modal')).at(-1);
        const listedNames = Array.from(secondWindow.querySelectorAll('.graphite-secret-list .setting-item-name')).map((name) => name.textContent);
        assert.deepEqual(listedNames, ['notion-token']);
        Array.from(secondWindow.querySelectorAll('button')).find((button) => button.textContent === 'Unlink').click();
        assert.deepEqual(chosenNames, ['notion-token', null]);
        // A setting's row takes one as Obsidian's do, and an element alone still works.
        new Setting(document.body.createDiv()).addComponent((controlElement) => new SecretComponent(harness.app, controlElement).setValue('notion-token'));
        assert.equal(new SecretComponent(document.body.createDiv()).setValue('x').getValue(), 'x');
    } finally {
        harness.close();
    }
});

test('generateMarkdownLink gives a link, never an embed, and getAssignedWidget gives a property\'s assigned type', async () => {
    // Checked in Obsidian 1.14 on the Mac: no `!` for notes, pictures, PDFs or bases.
    const files = { 'Note.md': 'x', 'Lectures.base': 'views: []\n', 'picture.png': 'p', '.obsidian/types.json': '{"types":{"Date":"date"}}' };
    const harness = await startRuntime({ files });
    try {
        const app = harness.app;
        await app.metadataTypeManager.loadTypes();
        for (const path of ['Note.md', 'Lectures.base', 'picture.png']) {
            assert.ok(!app.fileManager.generateMarkdownLink(app.vault.getFileByPath(path), 'Note.md').startsWith('!'), path);
        }
        assert.equal(app.fileManager.generateMarkdownLink(app.vault.getFileByPath('Lectures.base'), 'Note.md'), '[[Lectures.base]]');
        assert.equal(app.metadataTypeManager.getAssignedWidget('date'), 'date');
        assert.equal(app.metadataTypeManager.getAssignedWidget('Status'), null);
    } finally {
        harness.close();
    }
});
