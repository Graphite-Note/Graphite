/**
 * File: notion-import.test.js
 * ---------------------------
 * Layer: Tests
 * Description: Obsidian's Importer, unmodified, importing made-up Notion exports in the runtime.
 *
 * Authors: Bahey Shalash
 * Version: 1.1
 * Date: 17/11/2026
 */

// Obsidian's own Importer (compatibility-plugins.json pins it) imports Notion's HTML export on the
// plugin panel, walked as a person walks it. The exports are made up (support/notion-export-fixture.js),
// and the import is compared file by file with the expected one beside the tests
// (fixtures/notion-html-import-expected.json). Set GRAPHITE_UPDATE_EXPECTATIONS=1 to write it again
// after a deliberate change, and read the difference before committing it. Skipped when Importer is
// not built.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fileSystem = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { plain, settle } = require('../support/runtime-harness');
const notionExport = require('../support/notion-export-fixture');
const { importerPackage, startImporter, runNotionFileImport, vaultSnapshot, committedImportDifferences } = require('../support/notion-import-driver');

const expectationPath = path.join(__dirname, '..', 'fixtures', 'notion-html-import-expected.json');
const skip = importerPackage() ? false : 'Importer is not built (npm run build-compatibility-plugins)';

/// Importer writes a link to a page whose title it shortened with "...", while the file it writes
/// drops the trailing dots, as every platform's file names do there: its own bug, the same in
/// Obsidian, so the one link that stays unresolved.
const shortenedTitleLink = 'A very long title A very long title A very long title A very long title A very long title A very long title '
    + 'A very long title A very long title A very long title A very long title A very long title A...';

function pageErrors(harness) {
    return harness.consoleMessages.filter((message) => message.level === 'error').map((message) => message.text);
}

test('the committed small export, which the app\'s hosted test imports, is the one the generator makes', () => {
    const committed = fileSystem.readFileSync(path.join(__dirname, '..', 'fixtures', 'notion-small-export.zip'));
    assert.ok(committed.equals(notionExport.notionExportArchive(notionExport.makeSmallWorkspace(), 2)),
        'write it again with: node support/notion-export-fixture.js small fixtures/notion-small-export.zip');
});

test('Importer 3.2.0 loads and imports a two-part Notion HTML export exactly as expected, file by file', { skip }, async () => {
    const { harness, answer } = await startImporter();
    try {
        assert.deepEqual(answer, { isLoaded: true });
        const archive = fileSystem.readFileSync(path.join(__dirname, '..', 'fixtures', 'notion-small-export.zip'));
        const summary = await runNotionFileImport(harness, [{ name: 'Export-study-notes.zip', bytes: archive }]);
        assert.deepEqual({ imported: summary.imported, attachments: summary.attachments, skipped: summary.skipped, failed: summary.failed },
            { imported: 17, attachments: 2, skipped: 0, failed: 0 }, summary.text);
        const snapshot = vaultSnapshot(harness, '');
        if (process.env.GRAPHITE_UPDATE_EXPECTATIONS === '1') {
            fileSystem.mkdirSync(path.dirname(expectationPath), { recursive: true });
            fileSystem.writeFileSync(expectationPath, JSON.stringify(snapshot, null, 2) + '\n');
        }
        const expected = JSON.parse(fileSystem.readFileSync(expectationPath, 'utf8'));
        assert.deepEqual(Object.keys(snapshot).sort(), Object.keys(expected).sort(), 'the same files, in the same folders');
        for (const vaultPath of Object.keys(expected)) assert.equal(snapshot[vaultPath], expected[vaultPath], vaultPath);
        assert.deepEqual(committedImportDifferences(harness, Object.keys(expected).filter((vaultPath) => vaultPath !== 'Welcome.md')), [],
            'Tests/NotionImportedVault holds this import (GRAPHITE_UPDATE_EXPECTATIONS=1 writes it)');
        assert.deepEqual(plain(harness.host.notificationsOf('plugin.unsupportedFeature')), []);
        assert.deepEqual(pageErrors(harness), []);
    } finally {
        harness.close();
    }
});

test('every link and embed of the import resolves, but for Importer\'s own shortened title', { skip }, async () => {
    const { harness } = await startImporter();
    try {
        await runNotionFileImport(harness, [{ name: 'Export-study-notes.zip', bytes: notionExport.notionExportArchive(notionExport.makeSmallWorkspace(), 1) }]);
        await harness.waitForMetadata();
        const unresolved = plain(harness.app.metadataCache.unresolvedLinks);
        const unresolvedTargets = Object.values(unresolved).flatMap((targets) => Object.keys(targets));
        assert.deepEqual(unresolvedTargets, [shortenedTitleLink]);
        const resolved = plain(harness.app.metadataCache.resolvedLinks);
        const signalsNote = 'Notion/Study Notes/Signals and Systems/Signals and Systems.md';
        assert.deepEqual(Object.keys(resolved[signalsNote]).sort(), [
            'Notion/Study Notes/Signals and Systems/Lectures/Lectures.md', 'Problem set 1.pdf', 'spectrum plot.png']);
    } finally {
        harness.close();
    }
});

test('Notion\'s Markdown export is refused with Importer\'s reason, when chosen and when imported, and nothing is written', { skip }, () => {
    const runner = path.join(__dirname, '..', 'support', 'notion-markdown-export-run.js');
    const output = execFileSync(process.execPath, [runner], { encoding: 'utf8', timeout: 60000 });
    const result = JSON.parse(output);
    // The file list says so as soon as the export is chosen; going on anyway ends in the same reason.
    assert.deepEqual(result.unhandledReasons, ['This is a Markdown export. Export your Notion workspace as HTML instead.']);
    assert.equal(result.outcome, 'finished');
    assert.ok(result.shownText.includes('1failed'), result.shownText.slice(0, 400));
    assert.ok(result.shownText.includes('because it is a Markdown export; export your Notion workspace as HTML instead'), result.shownText.slice(0, 400));
    assert.deepEqual(result.importedPaths, []);
});

test('a truncated export ends with its failure named, never a crash or a hang', { skip }, async () => {
    const { harness } = await startImporter();
    try {
        const whole = notionExport.notionExportPart(notionExport.makeSmallWorkspace(), 1, 1);
        const truncated = whole.subarray(0, Math.floor(whole.length * 0.6));
        const summary = await runNotionFileImport(harness, [{ name: 'Export-truncated.zip', bytes: truncated }]);
        assert.ok(summary.failed >= 1, summary.text);
        assert.match(summary.log.join('\n'), /Export-truncated\.zip/);
        assert.equal(summary.imported, 0, 'a zip without its directory cannot be read at all');
    } finally {
        harness.close();
    }
});

test('one part of a split export imports on its own, its links to the other part left as links', { skip }, async () => {
    const { harness } = await startImporter();
    try {
        const workspace = notionExport.makeSmallWorkspace();
        const firstPart = notionExport.notionExportPart(workspace, 2, 1);
        const summary = await runNotionFileImport(harness, [{ name: 'Export-Part-1.zip', bytes: firstPart }]);
        assert.equal(summary.failed, 0, summary.text);
        assert.ok(summary.imported > 0 && summary.imported < 17, 'only the first part\'s pages: ' + summary.imported);
        assert.deepEqual(pageErrors(harness), []);
    } finally {
        harness.close();
    }
});

/// Imports `archive`, lets `edit` change the vault, and imports the same archive again, as a person
/// does after a new export: Done, then Importer's settings again.
async function importTwice(harness, archive, edit) {
    await runNotionFileImport(harness, [{ name: 'Export-study-notes.zip', bytes: archive }]);
    await edit();
    harness.window.document.querySelectorAll('.importer-button-bar button.mod-cta').forEach((button) => button.click());
    await settle();
    return runNotionFileImport(harness, [{ name: 'Export-study-notes.zip', bytes: archive }]);
}

async function editThroughVault(harness, vaultPath, addition) {
    // An edit made in Graphite reaches plugins as any vault change does; the note's date is now.
    const editedText = harness.readVaultFile(vaultPath) + addition;
    await harness.app.vault.modify(harness.app.vault.getAbstractFileByPath(vaultPath), editedText);
    return editedText;
}

test('imported notes carry their Notion page\'s time, and importing again keeps a row edited since', { skip }, async () => {
    const { harness } = await startImporter();
    try {
        const archive = notionExport.notionExportArchive(notionExport.makeSmallWorkspace(), 1);
        const editedRow = 'Notion/Study Notes/Signals and Systems/Lectures/Lecture 1- Signals.md';
        const untouchedRow = 'Notion/Study Notes/Signals and Systems/Lectures/Lecture 2- Systems.md';
        let editedText = null;
        let untouchedModified = null;
        const summary = await importTwice(harness, archive, async () => {
            // The row's "Last edited" time is the file's modification time, as in Obsidian.
            untouchedModified = harness.app.vault.getAbstractFileByPath(untouchedRow).stat.mtime;
            assert.equal(new Date(untouchedModified).getFullYear(), 2026);
            assert.equal(new Date(untouchedModified).getMonth(), 9, 'October, the row\'s last edit in Notion');
            editedText = await editThroughVault(harness, editedRow, '\nMy own addition after the import.\n');
        });
        assert.equal(summary.failed, 0, summary.text);
        assert.equal(harness.readVaultFile(editedRow), editedText, 'the edit is kept');
        assert.match(summary.log.join('\n'), /Lecture 1- Signals.*edited/);
        assert.equal(harness.app.vault.getAbstractFileByPath(untouchedRow).stat.mtime, untouchedModified);
        assert.deepEqual(plain(harness.host.notificationsOf('plugin.unsupportedFeature')), []);
        assert.deepEqual(pageErrors(harness), []);
    } finally {
        harness.close();
    }
});

test('importing again: Importer\'s own handling of pages without times and of parent pages, the same in Obsidian', { skip }, async () => {
    // Recorded so a change in Importer shows: Notion's HTML export gives ordinary pages no times,
    // so Importer compares their text, and a page edited since reads as changed in Notion and is
    // written over. A page with subpages finds its folder taken by the first import and gets links
    // to a folder with " 1", and attachments are copied again. Both are Importer's, in its shared
    // code, not Graphite's; Docs/Notion-import-todo.md section 4 keeps them for the fork.
    const { harness } = await startImporter();
    try {
        const archive = notionExport.notionExportArchive(notionExport.makeSmallWorkspace(), 1);
        const leafPage = 'Notion/Study Notes/Odd titles/Eigenvalues 🎯.md';
        const before = harness.readVaultFile.bind(harness);
        let firstImportText = null;
        const summary = await importTwice(harness, archive, async () => {
            firstImportText = before(leafPage);
            await editThroughVault(harness, leafPage, '\nMy own addition after the import.\n');
        });
        assert.equal(summary.failed, 0, summary.text);
        assert.equal(harness.readVaultFile(leafPage), firstImportText, 'the edit is written over');
        assert.match(harness.readVaultFile('Notion/Study Notes/Study Notes.md'), /\[\[Study Notes 1\/Signals and Systems\/Signals and Systems\|/);
        assert.equal(harness.vaultFileExists('spectrum plot 1.png'), true);
        assert.deepEqual(pageErrors(harness), []);
    } finally {
        harness.close();
    }
});
