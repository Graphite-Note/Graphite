/**
 * File: meta-bind-driver.js
 * -------------------------
 * Layer: Tests
 * Description: Runs Meta Bind's release in the runtime with the plugins it works with, draws a
 *              note as Graphite's reading view asks for it, and presses its buttons and fields.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

// Graphite's reading view asks the runtime for each block of a note that a plugin draws: a fenced
// block in a language a plugin registered (`codeBlock.render`), and, while a plugin registered a
// post-processor, each section of Markdown (`kind: section`). Its copies then send taps and typed
// text back by element path (`codeBlock.event`). This driver does the same for a whole note, so a
// test can press "New assignment" by its label as a person presses it. Meta Bind and the plugins
// beside it come from compatibility/built (`npm run build-compatibility-plugins`).
'use strict';

const fileSystem = require('node:fs');
const path = require('node:path');
const { startRuntime, installAndLoadPlugin, plain, settle } = require('./runtime-harness');

const builtFolder = path.join(__dirname, '..', 'compatibility', 'built');
const metaBindIdentifier = 'obsidian-meta-bind-plugin';

/// A plugin built or downloaded by the build script, or null when it is not there.
function builtPlugin(pluginIdentifier) {
    const folder = path.join(builtFolder, pluginIdentifier);
    if (!fileSystem.existsSync(path.join(folder, 'main.js'))) return null;
    const read = (name) => (fileSystem.existsSync(path.join(folder, name)) ? fileSystem.readFileSync(path.join(folder, name), 'utf8') : '');
    return { manifest: JSON.parse(read('manifest.json')), mainSource: read('main.js'), styles: read('styles.css') };
}

/// Every file of a folder on disk, by vault path, as `startRuntime` takes a vault.
function vaultFilesInFolder(folder) {
    const files = {};
    for (const relativePath of fileSystem.readdirSync(folder, { recursive: true })) {
        const location = path.join(folder, relativePath);
        if (fileSystem.statSync(location).isFile()) files[relativePath.split(path.sep).join('/')] = fileSystem.readFileSync(location, 'utf8');
    }
    return files;
}

/// Starts the runtime on `files` with `notePath` open in the reading view, loads the plugins
/// (Meta Bind last, as a vault lists it after the plugins it calls), and waits for layout-ready.
async function startWithMetaBind(options) {
    const harness = await startRuntime({ files: options.files });
    await harness.waitForMetadata();
    await harness.send({ operation: 'workspace.activeDocument', activeDocument: { path: options.notePath, mode: 'reading', editorSnapshot: harness.host.openNote(options.notePath, 0) } });
    const answers = {};
    for (const pluginIdentifier of (options.otherPlugins || []).concat([metaBindIdentifier])) {
        const pluginPackage = builtPlugin(pluginIdentifier);
        const dataPath = '.obsidian/plugins/' + pluginIdentifier + '/data.json';
        if (options.pluginData && options.pluginData[pluginIdentifier]) pluginPackage.data = options.pluginData[pluginIdentifier];
        else if (options.files[dataPath]) pluginPackage.data = JSON.parse(options.files[dataPath]);
        answers[pluginIdentifier] = plain(await installAndLoadPlugin(harness, pluginPackage));
    }
    await harness.send({ operation: 'plugins.layoutReady' });
    await settle();
    await settle();
    return { harness, answers };
}

/// The blocks of a note Graphite's reading view would ask plugins for: each fenced block in a
/// language a plugin draws, and each other section (paragraph, list, table) once a plugin has a
/// post-processor. Lines are counted from the note's first line, frontmatter included.
function readingBlocks(noteText, drawnLanguages) {
    const lines = noteText.split('\n');
    const blocks = [];
    let lineIndex = 0;
    if (lines[0] === '---') {
        lineIndex = lines.indexOf('---', 1) + 1;
    }
    while (lineIndex < lines.length) {
        if (lines[lineIndex].trim() === '') { lineIndex += 1; continue; }
        const fence = lines[lineIndex].match(/^```\s*(\S*)/);
        if (fence) {
            const closingIndex = lines.findIndex((line, index) => index > lineIndex && line.startsWith('```'));
            const lastIndex = closingIndex === -1 ? lines.length - 1 : closingIndex;
            if (drawnLanguages.includes(fence[1])) {
                blocks.push({ kind: 'codeBlock', language: fence[1], source: lines.slice(lineIndex + 1, lastIndex).join('\n'), firstLine: lineIndex, lineCount: lastIndex - lineIndex + 1 });
            }
            lineIndex = lastIndex + 1;
            continue;
        }
        const firstLine = lineIndex;
        while (lineIndex < lines.length && lines[lineIndex].trim() !== '' && !lines[lineIndex].startsWith('```')) lineIndex += 1;
        blocks.push({ kind: 'section', source: lines.slice(firstLine, lineIndex).join('\n'), firstLine, lineCount: lineIndex - firstLine });
    }
    return blocks;
}

/// Draws every block of the note as the reading view asks for it, in order, and returns them
/// with the identifiers Graphite gave them and the HTML of their copies.
async function drawNote(harness, notePath, identifierPrefix) {
    const noteText = harness.readVaultFile(notePath);
    const drawnLanguages = plain(harness.host.notificationsOf('codeBlocks.changed').at(-1)).languages;
    const blocks = readingBlocks(noteText, drawnLanguages);
    for (let blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
        const block = blocks[blockIndex];
        block.blockIdentifier = (identifierPrefix || 'block') + '-' + blockIndex;
        const message = { operation: 'codeBlock.render', blockIdentifier: block.blockIdentifier, source: block.source, sourcePath: notePath, firstLine: block.firstLine, lineCount: block.lineCount, noteText, width: 640 };
        if (block.kind === 'section') message.kind = 'section';
        else message.language = block.language;
        const answer = plain(await harness.send(message));
        block.html = answer.html || '';
        block.isChanged = block.kind === 'codeBlock' || Boolean(answer.isChanged);
    }
    await settle();
    return blocks;
}

/// The HTML a copy shows now: the last change the runtime sent for the block, or what it drew.
function currentHTML(harness, block) {
    const change = harness.host.notificationsOf('codeBlock.changed').filter((notification) => notification.blockIdentifier === block.blockIdentifier).at(-1);
    return change ? plain(change).html : block.html;
}

/// The copy's page as Graphite builds it from the HTML the runtime sent: parsed, then each
/// `graphite-p` made a `p` again (CommunityPluginCodeBlockPage.script, keepParagraphsWhole).
function parseCopy(harness, html) {
    const document = harness.window.document;
    const template = document.createElement('template');
    template.innerHTML = html;
    for (const kept of Array.from(template.content.querySelectorAll('graphite-p'))) {
        const paragraph = document.createElement('p');
        for (const attribute of Array.from(kept.attributes)) paragraph.setAttribute(attribute.name, attribute.value);
        while (kept.firstChild) paragraph.appendChild(kept.firstChild);
        kept.replaceWith(paragraph);
    }
    return template;
}

/// The element path a copy sends for the first element matching `selector` (and `text`, when
/// given): the position among element children at each level, from the copy's outer element.
function elementPath(harness, html, selector, text) {
    const template = parseCopy(harness, html);
    const root = template.content.firstElementChild;
    if (!root) return null;
    const target = Array.from(root.querySelectorAll(selector)).find((element) => text === undefined || element.textContent.trim() === text);
    if (!target) return null;
    const indexes = [];
    for (let element = target; element !== root; element = element.parentElement) indexes.unshift(Array.from(element.parentElement.children).indexOf(element));
    return indexes;
}

/// The block whose copy shows `selector` (with `text`), and the path to it.
function findInBlocks(harness, blocks, selector, text) {
    for (const block of blocks) {
        const html = currentHTML(harness, block);
        const foundPath = elementPath(harness, html, selector, text);
        if (foundPath) return { block, elementPath: foundPath };
    }
    return null;
}

/// Taps the button labelled `label` in the drawn note, as the copy forwards a tap.
async function pressButton(harness, blocks, label) {
    const found = findInBlocks(harness, blocks, 'button.mb-button-inner', label);
    if (!found) throw new Error('No button labelled “' + label + '” is drawn.');
    return plain(await harness.send({ operation: 'codeBlock.event', blockIdentifier: found.block.blockIdentifier, elementPath: found.elementPath }));
}

/// Text typed into, or a choice made in, the field of Meta Bind's input field of `inputType`
/// bound to the property `bindTarget`, as the copy forwards typing.
async function enterInField(harness, blocks, inputType, selector, value, occurrence) {
    const candidates = blocks.filter((block) => elementPath(harness, currentHTML(harness, block), '.mb-input-type-' + inputType + ' ' + selector));
    const block = candidates[occurrence || 0];
    if (!block) throw new Error('No ' + inputType + ' field is drawn.');
    const foundPath = elementPath(harness, currentHTML(harness, block), '.mb-input-type-' + inputType + ' ' + selector);
    return plain(await harness.send({ operation: 'codeBlock.event', blockIdentifier: block.blockIdentifier, eventType: 'input', elementPath: foundPath, value }));
}

/// The note's frontmatter as the vault's metadata cache reads it.
function frontmatterOf(harness, notePath) {
    const file = harness.app.vault.getFileByPath(notePath);
    const cache = file ? harness.app.metadataCache.getFileCache(file) : null;
    return plain(cache && cache.frontmatter) || null;
}

/// Waits until Meta Bind's metadata cycle (every 200 ms) has written what it holds.
async function waitForMetaBindWrites() {
    await new Promise((resolve) => setTimeout(resolve, 700));
    await settle();
}

/// What the page logged as errors and warnings: Meta Bind logs a failed action as a warning.
function pageErrors(harness) {
    return harness.consoleMessages.filter((message) => message.level === 'error' || message.level === 'warn').map((message) => message.text);
}

module.exports = {
    builtPlugin, vaultFilesInFolder, startWithMetaBind, readingBlocks, drawNote, currentHTML, parseCopy, elementPath,
    findInBlocks, pressButton, enterInField, frontmatterOf, waitForMetaBindWrites, pageErrors, metaBindIdentifier,
};
