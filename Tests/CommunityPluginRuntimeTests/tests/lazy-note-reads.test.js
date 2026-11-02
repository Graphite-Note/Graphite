/**
 * File: lazy-note-reads.test.js
 * -----------------------------
 * Layer: Tests
 * Description: What plugins cost at start-up: no note read until asked for, pages of the file list, and saving
 *              settings.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

// What plugins cost at start-up: no note is read until something asks for one, and a plugin
// that asks for the whole vault gets it behind what a person waits for.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime, installAndLoadPlugin, plain, settle } = require('../support/runtime-harness');

const manifest = { id: 'example', name: 'Example', version: '1.0.0', minAppVersion: '1.0.0', description: 'Test', author: 'Graphite' };

function manyNotes(count) {
    const files = {};
    for (let position = 0; position < count; position += 1) files['Note ' + position + '.md'] = '---\nnumber: ' + position + '\n---\n# Note ' + position + '\n';
    return files;
}

function readsOf(harness) {
    return plain(harness.host.requests.filter((request) => request.operation === 'vault.read' && String(request.path).endsWith('.md')));
}

test('a vault of many notes starts plugins without reading a single note', async () => {
    const harness = await startRuntime({ files: manyNotes(120) });
    try {
        const source = `"use strict";
var obsidian = require("obsidian");
module.exports = class extends obsidian.Plugin {
    onload() { this.addCommand({ id: 'nothing', name: 'Nothing', callback() {} }); }
};`;
        await installAndLoadPlugin(harness, { manifest, mainSource: source });
        await harness.send({ operation: 'plugins.layoutReady' });
        await settle();
        assert.equal(readsOf(harness).length, 0, 'before this took 120 reads, one per note, on every launch');
    } finally {
        harness.close();
    }
});

test('asking for one note reads that note, once, and says when it arrives', async () => {
    const harness = await startRuntime({ files: manyNotes(120) });
    try {
        const cache = harness.app.metadataCache;
        const changed = [];
        cache.on('changed', (file) => changed.push(file.path));
        const note = harness.app.vault.getFileByPath('Note 7.md');
        assert.equal(cache.getFileCache(note), null, 'not read yet');
        assert.equal(cache.getFileCache(note), null, 'asking again does not ask for a second read');
        await settle();
        assert.equal(cache.getFileCache(note).frontmatter.number, 7);
        assert.deepEqual(changed, ['Note 7.md']);
        assert.deepEqual(readsOf(harness).map((read) => read.path), ['Note 7.md']);
    } finally {
        harness.close();
    }
});

test('a note that cannot be read is not read again each time it is asked for, until it changes', async () => {
    const harness = await startRuntime({ files: { 'Cloud.md': '# Cloud\n' } });
    try {
        harness.host.notDownloadedPaths.add('Cloud.md');
        const cache = harness.app.metadataCache;
        const note = harness.app.vault.getFileByPath('Cloud.md');
        cache.getFileCache(note);
        await settle();
        cache.getFileCache(note);
        await settle();
        assert.equal(readsOf(harness).length, 1);
        harness.host.notDownloadedPaths.delete('Cloud.md');
        await harness.send({ operation: 'vault.changes', changes: [{ path: 'Cloud.md', isReloadNeeded: true }] });
        await settle();
        assert.equal(cache.getFileCache(note).headings[0].heading, 'Cloud');
    } finally {
        harness.close();
    }
});

test('a plugin waiting for resolved gets every note read, once, with the event only when all are', async () => {
    const harness = await startRuntime({ files: manyNotes(12) });
    try {
        const cache = harness.app.metadataCache;
        let resolvedCount = 0;
        cache.on('resolved', () => { resolvedCount += 1; });
        cache.getFileCache(harness.app.vault.getFileByPath('Note 1.md'));
        await settle();
        assert.equal(resolvedCount, 0, 'one note read on demand is not the whole vault');
        await harness.waitForMetadata();
        assert.equal(resolvedCount, 1);
        assert.equal(readsOf(harness).length, 12, 'the note read on demand is not read again');
        assert.equal(cache.getCachedFiles().length, 12);
    } finally {
        harness.close();
    }
});

test('a plugin that walks the vault with getFileCache starts the pass instead of waiting one miss at a time', async () => {
    const harness = await startRuntime({ files: manyNotes(100) });
    try {
        const cache = harness.app.metadataCache;
        assert.equal(cache.wholeVaultReadTimer, null);
        for (const note of harness.app.vault.getMarkdownFiles()) cache.getFileCache(note);
        assert.notEqual(cache.wholeVaultReadTimer, null, 'the pass is on its way');
    } finally {
        harness.close();
    }
});

test('asking for the tags, the backlinks or the links of the vault starts the pass', async () => {
    for (const ask of [
        (cache) => cache.getTags(),
        (cache, app) => cache.getBacklinksForFile(app.vault.getFileByPath('Note 0.md')),
        (cache) => cache.resolvedLinks,
        (cache) => cache.unresolvedLinks,
        (cache) => cache.getAllPropertyInfos(),
        (cache) => cache.getFrontmatterPropertyValuesForKey('number'),
    ]) {
        const harness = await startRuntime({ files: manyNotes(2) });
        try {
            assert.equal(harness.app.metadataCache.wholeVaultReadTimer, null);
            ask(harness.app.metadataCache, harness.app);
            assert.notEqual(harness.app.metadataCache.wholeVaultReadTimer, null, String(ask));
        } finally {
            harness.close();
        }
    }
});

test('a note opened for the person is read, ahead of the pass, and the pass waits', async () => {
    const harness = await startRuntime({ files: manyNotes(8) });
    try {
        const cache = harness.app.metadataCache;
        await harness.send({ operation: 'workspace.activeDocument', activeDocument: { path: 'Note 3.md', mode: 'livePreview', editorSnapshot: harness.host.openNote('Note 3.md', 0) } });
        await settle();
        assert.deepEqual(readsOf(harness).map((read) => read.path), ['Note 3.md']);
        assert.ok(cache.backgroundReadsWaitUntil > Date.now(), 'the person is at work, so the vault waits');
    } finally {
        harness.close();
    }
});

test('a code block is drawn with its note\'s frontmatter although nothing read the note before', async () => {
    const harness = await startRuntime({ files: { 'Note.md': '---\nstatus: open\n---\n```show\n```\n' } });
    try {
        const source = `"use strict";
var obsidian = require("obsidian");
module.exports = class extends obsidian.Plugin {
    onload() { this.registerMarkdownCodeBlockProcessor('show', (code, element, context) => { element.setText(String(context.frontmatter && context.frontmatter.status)); }); }
};`;
        await installAndLoadPlugin(harness, { manifest, mainSource: source });
        const answer = plain(await harness.send({ operation: 'codeBlock.render', blockIdentifier: 'block', language: 'show', source: '', sourcePath: 'Note.md', width: 400 }));
        assert.match(answer.html, />open</);
    } finally {
        harness.close();
    }
});

test('a large vault\'s file list arrives page by page, whole', async () => {
    const harness = await startRuntime({ files: manyNotes(25), isStarting: false });
    try {
        harness.host.listingPageSize = 10;
        await harness.send({ operation: 'runtime.start', vault: { name: 'Test', identifier: 'pages', configuration: {} }, device: {}, recentFiles: [] });
        harness.app = harness.runtime.app;
        const listings = plain(harness.host.requests.filter((request) => request.operation === 'vault.list'));
        assert.equal(listings.length, 3, 'three messages of ten entries at most, not one of twenty-five');
        assert.equal(harness.app.vault.getMarkdownFiles().length, 25);
    } finally {
        harness.close();
    }
});

test('a plugin keeps saving its settings after another device changed its data file', async () => {
    const harness = await startRuntime({ files: { 'Note.md': 'x\n', '.obsidian/plugins/example/data.json': '{"from":"start"}' } });
    try {
        const source = `"use strict";
var obsidian = require("obsidian");
module.exports = class extends obsidian.Plugin {
    async onload() { this.settings = await this.loadData(); }
};`;
        await installAndLoadPlugin(harness, { manifest, mainSource: source });
        const plugin = harness.app.plugins.getPlugin('example');
        // Obsidian on another device changes the file, and iCloud brings it here.
        harness.writeVaultFile('.obsidian/plugins/example/data.json', '{"from":"other device"}');
        await harness.send({ operation: 'vault.changes', changes: [{ path: '.obsidian/plugins/example/data.json', isReloadNeeded: true }] });
        await plugin.saveData({ from: 'this device' });
        assert.deepEqual(JSON.parse(harness.readVaultFile('.obsidian/plugins/example/data.json')), { from: 'this device' }, 'it overwrites, as in Obsidian');
        assert.deepEqual(plain(harness.host.notificationsOf('plugin.writeConflict')), []);
    } finally {
        harness.close();
    }
});

test('a plugin that takes over notes by their frontmatter finds it, although nothing read the note before', async () => {
    const harness = await startRuntime({ files: { 'Drawing.md': '---\nexample-plugin: parsed\n---\nA drawing\n' } });
    try {
        const source = `"use strict";
var obsidian = require("obsidian");
class DrawingView extends obsidian.ItemView {
    getViewType() { return 'drawing'; }
    getDisplayText() { return 'Drawing'; }
}
module.exports = class extends obsidian.Plugin {
    onload() {
        const plugin = this;
        this.registerView('drawing', (leaf) => new DrawingView(leaf));
        const original = obsidian.WorkspaceLeaf.prototype.setViewState;
        obsidian.WorkspaceLeaf.prototype.setViewState = function (state, result) {
            const cache = state.state && state.state.file ? plugin.app.metadataCache.getCache(state.state.file) : null;
            if (state.type === 'markdown' && cache && cache.frontmatter && cache.frontmatter['example-plugin']) return original.call(this, Object.assign({}, state, { type: 'drawing' }), result);
            return original.call(this, state, result);
        };
        this.register(() => { obsidian.WorkspaceLeaf.prototype.setViewState = original; });
    }
};`;
        await installAndLoadPlugin(harness, { manifest, mainSource: source });
        const opened = plain(await harness.send({ operation: 'file.openInView', path: 'Drawing.md' }));
        assert.equal(opened.isOpened, true, 'before, a note opened early showed as plain text');
    } finally {
        harness.close();
    }
});
