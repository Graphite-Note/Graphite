/**
 * File: notion-api-import.test.js
 * -------------------------------
 * Layer: Tests
 * Description: Obsidian's Importer, unmodified, importing a made-up workspace through Notion's API, and Notion failing.
 *
 * Authors: Bahey Shalash
 * Version: 1.1
 * Date: 17/11/2026
 */

// Obsidian's own Importer imports a made-up Notion workspace through Notion's API on the plugin panel,
// walked as a person walks it: the token linked with its secret control, the pages loaded and chosen,
// Continue until Done. Notion is the test host's network (support/notion-api-fixture.js answers as
// Notion's API does), so each failure can be made: a revoked token, the rate limit, server errors, a page
// no longer shared, the network gone. The import is compared file by file with
// fixtures/notion-api-import-expected.json; GRAPHITE_UPDATE_EXPECTATIONS=1 writes it again. Skipped when
// Importer is not built.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fileSystem = require('node:fs');
const path = require('node:path');
const { plain } = require('../support/runtime-harness');
const { makeNotionResponder, notionTestToken } = require('../support/notion-api-fixture');
const { importerPackage, startImporter, runNotionApiImport, vaultSnapshot, committedImportDifferences } = require('../support/notion-import-driver');

const expectationPath = path.join(__dirname, '..', 'fixtures', 'notion-api-import-expected.json');
/// The answers of the import, by request, which the app's hosted test gives Graphite's native requests (`NotionAnswers`).
const answersPath = path.join(__dirname, '..', 'fixtures', 'notion-api-answers.json');
const skip = importerPackage() ? false : 'Importer is not built (npm run build-compatibility-plugins)';

async function importThroughApi(failures, secret) {
    const { harness } = await startImporter();
    const notion = makeNotionResponder(failures);
    notion.answers = {};
    harness.host.networkResponder = (message) => {
        const answer = notion.responder(message);
        notion.answers[message.method.toUpperCase() + ' ' + new URL(message.url).pathname] = answer;
        return answer;
    };
    const summary = await runNotionApiImport(harness, secret || notionTestToken);
    return { harness, notion, summary, notices: plain(harness.host.notificationsOf('notice.show').map((notice) => notice.message)) };
}

test('Importer 3.2.0 imports a workspace through Notion\'s API: notes, a base for the database, property types', { skip }, async () => {
    const { harness, notion, summary } = await importThroughApi({});
    try {
        const answers = JSON.stringify(Object.fromEntries(Object.keys(notion.answers).sort().map((key) => [key, notion.answers[key]])), null, 2);
        if (process.env.GRAPHITE_UPDATE_EXPECTATIONS === '1') fileSystem.writeFileSync(answersPath, answers.replace(/\n$/, '') + '\n');
        assert.deepEqual(JSON.parse(fileSystem.readFileSync(answersPath, 'utf8')), notion.answers, 'fixtures/notion-api-answers.json holds the answers');
        assert.deepEqual({ imported: summary.imported, failed: summary.failed }, { imported: 3, failed: 0 }, summary.text || summary.stoppedAt);
        const snapshot = vaultSnapshot(harness, 'Notion');
        snapshot['.obsidian/types.json'] = harness.readVaultFile('.obsidian/types.json');
        if (process.env.GRAPHITE_UPDATE_EXPECTATIONS === '1') fileSystem.writeFileSync(expectationPath, JSON.stringify(snapshot, null, 2) + '\n');
        const expected = JSON.parse(fileSystem.readFileSync(expectationPath, 'utf8'));
        assert.deepEqual(Object.keys(snapshot).sort(), Object.keys(expected).sort());
        for (const vaultPath of Object.keys(expected)) assert.equal(snapshot[vaultPath], expected[vaultPath], vaultPath);
        assert.deepEqual(committedImportDifferences(harness, Object.keys(expected)), [], 'Tests/NotionImportedVault holds this import');
        // The page embeds its database's base, as Obsidian's Importer writes it there.
        assert.match(snapshot['Notion/Signals and Systems/Signals and Systems.md'], /\n!\[\[Lectures\.base\]\]$/);
        assert.deepEqual(plain(harness.host.notificationsOf('plugin.unsupportedFeature')), []);
        assert.deepEqual(harness.consoleMessages.filter((message) => message.level === 'error').map((message) => message.text), []);
    } finally {
        harness.close();
    }
});

test('a revoked token, or no network at all, is said when the pages are loaded, and nothing is imported', { skip }, async () => {
    const cases = [[{ revokedToken: true }, 'API token is invalid.'], [{ isOffline: true }, 'The Internet connection appears to be offline.']];
    for (const [failures, reason] of cases) {
        const { harness, summary, notices } = await importThroughApi(failures);
        try {
            assert.ok(summary.stoppedAt, 'Importer offers no way on without pages');
            assert.deepEqual(notices, ['Failed to load pages: ' + reason]);
            assert.deepEqual(Object.keys(vaultSnapshot(harness, 'Notion')), []);
        } finally {
            harness.close();
        }
    }
});

test('Notion\'s rate limit and passing server errors during the import are waited out, and the import completes', { skip }, async () => {
    for (const failures of [{ rateLimitedRequests: 2, failingFromRequest: 3 }, { serverErrorRequests: 3, failingFromRequest: 3 }]) {
        const { harness, notion, summary } = await importThroughApi(failures);
        try {
            assert.deepEqual({ imported: summary.imported, failed: summary.failed }, { imported: 3, failed: 0 }, JSON.stringify(failures));
            assert.ok(notion.requests.length > 13, 'the refused requests were made again');
        } finally {
            harness.close();
        }
    }
});

test('server errors that go on, a page no longer shared, the network lost: each named, the rest imported, never a hang', { skip }, async () => {
    const persistent = await importThroughApi({ serverErrorRequests: 1000, failingFromRequest: 3 });
    try {
        assert.equal(persistent.summary.failed, 1);
        assert.match(persistent.summary.log.join('\n'), /Bad gateway\., and gave up after 3 retries/);
    } finally {
        persistent.harness.close();
    }
    const unshared = await importThroughApi({ unsharedAfterRequests: 5 });
    try {
        assert.equal(unshared.summary.imported, 1);
        assert.match(unshared.summary.log.join('\n'), /Page: Lecture 1: Signals .* because Could not find block/);
        assert.equal(unshared.harness.vaultFileExists('Notion/Signals and Systems/Signals and Systems.md'), true, 'the page still shared is imported');
    } finally {
        unshared.harness.close();
    }
    const lost = await importThroughApi({ offlineRequests: 2, failingFromRequest: 3 });
    try {
        assert.equal(lost.summary.failed, 1);
        assert.match(lost.summary.log.join('\n'), /Signals and Systems .* because The Internet connection appears to be offline\./);
        // The network back, importing again brings in what was missed.
        lost.harness.window.document.querySelectorAll('.importer-button-bar button.mod-cta').forEach((button) => button.click());
        const again = await runNotionApiImport(lost.harness, notionTestToken);
        assert.deepEqual({ imported: again.imported, failed: again.failed }, { imported: 3, failed: 0 }, again.text || again.stoppedAt);
    } finally {
        lost.harness.close();
    }
});

test('Importer\'s own failure: a rate limit or server error while the page list loads stops the list (the same in Obsidian)', { skip }, async () => {
    // Recorded so a change in Importer shows: its page list retries through a stand-in import context
    // without `shouldStop` (`readPages` in src/formats/notion-api.ts), so the first retry fails, and the
    // person sees "n.shouldStop is not a function". Refresh loads the list once Notion answers again.
    const { harness, summary, notices } = await importThroughApi({ rateLimitedRequests: 1 });
    try {
        assert.ok(summary.stoppedAt);
        assert.deepEqual(notices, ['Failed to load pages: n.shouldStop is not a function']);
    } finally {
        harness.close();
    }
});
