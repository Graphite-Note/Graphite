/**
 * File: notion-markdown-export-run.js
 * -----------------------------------
 * Layer: Tests
 * Description: Picks Notion's Markdown export in Importer, in a process of its own, and prints what happened.
 *
 * Authors: Bahey Shalash
 * Version: 1.0
 * Date: 17/11/2026
 */

// Importer refuses Notion's Markdown export by showing the reason in its file list and then letting
// the error go on unhandled. WebKit only logs that; Node's test runner would end the test, so the
// case runs here, in a process of its own, and prints a JSON summary for the test to read.
'use strict';

const notionExport = require('./notion-export-fixture');
const { startImporter, runNotionFileImport, vaultSnapshot } = require('./notion-import-driver');
const { settle } = require('./runtime-harness');

const unhandledReasons = [];
process.on('unhandledRejection', (reason) => unhandledReasons.push(String(reason && reason.message)));

(async () => {
    const { harness } = await startImporter();
    try {
        const archive = notionExport.notionMarkdownExportArchive(notionExport.makeSmallWorkspace());
        const outcome = await runNotionFileImport(harness, [{ name: 'Export-markdown.zip', bytes: archive }]).then(() => 'finished', (error) => error.message);
        await settle();
        const fileList = harness.window.document.querySelector('.setting-page:last-of-type') || harness.window.document.body;
        process.stdout.write(JSON.stringify({
            outcome,
            shownText: fileList.textContent,
            unhandledReasons,
            importedPaths: Object.keys(vaultSnapshot(harness, 'Notion')),
        }));
    } finally {
        harness.close();
    }
})();
