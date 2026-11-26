/**
 * File: meta-bind-runtime-gaps.test.js
 * ------------------------------------
 * Layer: Tests
 * Description: The runtime gaps running Meta Bind found, each fixed for every plugin and tested
 *              here with a small plugin of the same shape.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

// Running Meta Bind 1.5.1 (meta-bind.test.js) found two gaps of the runtime, not of Meta Bind:
// Obsidian's loaders of the libraries it bundles threw, so a plugin that waits for Prism before
// drawing drew an error instead; and a paragraph a plugin put a block into was split by the HTML
// parser in the copy, so taps and typing in the copy missed the plugin's elements.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime, installAndLoadPlugin, plain, settle } = require('../support/runtime-harness');
const { parseCopy } = require('../support/meta-bind-driver');

const manifest = { id: 'field-plugin', name: 'Field Plugin', version: '1.0.0', minAppVersion: '1.0.0' };

function pluginSource(body) {
    return "'use strict';\nconst obsidian = require('obsidian');\n" + body + '\nmodule.exports = FieldPlugin;';
}

test('Obsidian\'s library loaders resolve, as in Obsidian, reporting the library Graphite does not bundle', async () => {
    const harness = await startRuntime({ files: { 'Note.md': '```waits\n```\n' } });
    try {
        const source = pluginSource(`
class FieldPlugin extends obsidian.Plugin {
    async onload() {
        this.registerMarkdownCodeBlockProcessor('waits', async (source, element) => {
            const prism = await obsidian.loadPrism();
            element.createSpan({ cls: 'drawn', text: 'drawn, Prism ' + typeof prism });
        });
        window.loadedLibraries = await Promise.all([obsidian.loadMathJax(), obsidian.loadMermaid(), obsidian.loadPdfJs()]);
    }
}`);
        assert.deepEqual(plain(await installAndLoadPlugin(harness, { manifest, mainSource: source })), { isLoaded: true }, 'awaiting the loaders at load does not fail the plugin');
        const drawn = plain(await harness.send({ operation: 'codeBlock.render', blockIdentifier: 'block-1', language: 'waits', source: '', sourcePath: 'Note.md', width: 600 }));
        assert.match(drawn.html, /<span class="drawn">drawn, Prism undefined<\/span>/, 'a plugin that waits for Prism draws, and finds no Prism on the page');
        assert.doesNotMatch(drawn.html, /graphite-plugin-error/);
        await settle();
        assert.deepEqual(plain(harness.host.notificationsOf('plugin.unsupportedFeature').map((notification) => notification.featureName)).sort(),
            ['loadMathJax', 'loadMermaid', 'loadPdfJs', 'loadPrism'], 'each library is still named on the plugin\'s settings page');
        assert.deepEqual(plain(harness.host.notificationsOf('plugin.failure')), []);
    } finally {
        harness.close();
    }
});

test('a paragraph a plugin put a block into reaches the copy whole, so a tap in the copy finds the plugin\'s element', async () => {
    const noteText = 'Status `field:todo` today.\n';
    const harness = await startRuntime({ files: { 'Note.md': noteText } });
    try {
        // As Meta Bind draws an inline field: a div inside the paragraph's inline code.
        const source = pluginSource(`
class FieldPlugin extends obsidian.Plugin {
    async onload() {
        this.registerMarkdownPostProcessor((element) => {
            for (const code of Array.from(element.querySelectorAll('code'))) {
                if (!code.textContent.startsWith('field:')) continue;
                const value = code.textContent.slice('field:'.length);
                code.empty();
                const wrapper = code.createDiv({ cls: 'field-wrapper' });
                const button = wrapper.createEl('button', { cls: 'field-button', text: value });
                button.addEventListener('click', () => { button.setText(button.getText() === 'todo' ? 'done' : 'todo'); });
            }
        });
    }
}`);
        await installAndLoadPlugin(harness, { manifest, mainSource: source });
        const section = plain(await harness.send({ operation: 'codeBlock.render', kind: 'section', blockIdentifier: 'section-1', source: noteText.trim(), sourcePath: 'Note.md', firstLine: 0, lineCount: 1, noteText, width: 600 }));
        assert.equal(section.isChanged, true);
        assert.match(section.html, /<graphite-p>Status <code><div class="field-wrapper"><button class="field-button">todo<\/button><\/div><\/code> today\.<\/graphite-p>/);

        // Parsed as the copy parses it, the paragraph is one element again, holding the field.
        const copy = parseCopy(harness, section.html).content.firstElementChild;
        assert.equal(copy.children.length, 1, 'one paragraph, not a paragraph, a div and another paragraph');
        assert.equal(copy.firstElementChild.tagName, 'P');
        assert.equal(copy.querySelector('p > code > div.field-wrapper > button.field-button').textContent, 'todo');
        // Parsed as HTML alone, the parser splits it, which is what the copy showed before.
        const template = harness.window.document.createElement('template');
        template.innerHTML = section.html.replace(/graphite-p/g, 'p');
        assert.notEqual(template.content.firstElementChild.children.length, 1);

        // The path the copy sends for the button: paragraph, code, wrapper, button.
        const tap = plain(await harness.send({ operation: 'codeBlock.event', blockIdentifier: 'section-1', elementPath: [0, 0, 0, 0] }));
        assert.equal(tap.isHandled, true);
        assert.match(tap.html, /<button class="field-button">done<\/button>/, 'the plugin\'s own button heard the tap');

        // Paragraphs that hold only inline elements are sent as they are.
        const plainSection = plain(await harness.send({ operation: 'codeBlock.render', kind: 'section', blockIdentifier: 'section-2', source: 'Plain `code` here.', sourcePath: 'Note.md', firstLine: 0, lineCount: 1, noteText: 'Plain `code` here.\n', width: 600 }));
        assert.equal(plainSection.isChanged, false);
    } finally {
        harness.close();
    }
});

test('a plugin that finds no metadata while a read of the note is under way hears changed when the read ends', async () => {
    const harness = await startRuntime({ files: { 'Course.md': '---\nlectures_held: 1\n---\n# Course\n' } });
    try {
        const cache = harness.app.metadataCache;
        const file = harness.app.vault.getFileByPath('Course.md');
        const changes = [];
        cache.on('changed', (changedFile, text, metadata) => changes.push([changedFile.path, metadata.frontmatter && metadata.frontmatter.lectures_held]));
        // A block about to draw has its note read (readNoteOfBlock), and waits for it at most two
        // seconds; a plugin asking meanwhile, as Meta Bind does as it draws, finds nothing yet.
        const blockRead = cache.readNow([file]);
        assert.equal(cache.getFileCache(file), null);
        await blockRead;
        await settle();
        assert.equal(cache.getFileCache(file).frontmatter.lectures_held, 1);
        assert.deepEqual(changes, [['Course.md', 1]], 'the plugin is told the note\'s metadata is there');

    } finally {
        harness.close();
    }
});
