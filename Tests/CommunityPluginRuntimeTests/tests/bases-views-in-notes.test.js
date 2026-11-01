// A plugin's view of a base embedded in a note: each embed has a leaf of its own, shown as a
// copy, so several show at once, and each stays current. The fixture plugin draws a small
// week table from properties of the base's rows, the way a timetable does.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { startRuntime, installAndLoadPlugin, plain, settle } = require('../support/runtime-harness');

const manifest = { id: 'week-table', name: 'Week Table', version: '1.0.0', minAppVersion: '1.0.0', description: 'Test', author: 'Graphite' };

const weekTablePlugin = `"use strict";
var obsidian = require("obsidian");
class WeekTable extends obsidian.BasesView {
    constructor(controller, parent) {
        super(controller);
        this.type = 'week-table';
        this.selectedWeek = 1;
        this.containerEl = parent.createDiv('week-table');
        window.weekTables = (window.weekTables || 0) + 1;
    }
    onDataUpdated() {
        this.containerEl.empty();
        this.containerEl.createEl('h4', { text: String(this.config.get('title')) + ', week ' + this.selectedWeek });
        const next = this.containerEl.createEl('button', { cls: 'next-week', text: 'Next' });
        next.addEventListener('click', () => { this.selectedWeek += 1; this.onDataUpdated(); });
        for (const entry of this.data.data) {
            const day = entry.getValue('note.day');
            this.containerEl.createDiv({ cls: 'row', text: entry.file.basename + ': ' + (day instanceof obsidian.NullValue ? 'Missing' : day.toString()) });
        }
    }
    onResize() { window.weekTableResizes = (window.weekTableResizes || 0) + 1; }
}
module.exports = class extends obsidian.Plugin {
    onload() {
        this.registerBasesView('week-table', {
            name: 'Week table', icon: 'calendar-days',
            factory: (controller, parent) => new WeekTable(controller, parent),
            options: () => [
                { type: 'text', displayName: 'Heading', key: 'title', default: 'A week' },
                { type: 'group', displayName: 'Hours', items: [{ type: 'slider', displayName: 'First hour', key: 'firstHour', min: 6, max: 12, step: 1, default: 8 }] },
                { type: 'dropdown', displayName: 'Layout', key: 'layout', options: { compact: 'Compact', roomy: 'Roomy' } },
            ],
        });
    }
};`;

const baseText = 'views:\n  - type: week-table\n    name: First\n    title: First year\n  - type: week-table\n    name: Second\n    title: Second year\n';
const files = {
    'Plan.base': baseText,
    'Algebra.md': '---\nday: Monday\n---\n',
    'Physics.md': '---\nday: Tuesday\n---\n',
    'Masters.md': '![[Plan.base#First]]\n![[Plan.base#Second]]\n',
};

function openMessage(viewName, viewIndex, paths) {
    return { operation: 'basesView.open', viewType: 'week-table', viewName, viewIndex, baseFilePath: 'Plan.base', embedWidth: 600, groups: [{ key: null, paths }], properties: ['note.day'] };
}

async function loaded() {
    const harness = await startRuntime({ files });
    await installAndLoadPlugin(harness, { manifest, mainSource: weekTablePlugin });
    await settle();
    return harness;
}

function attach(harness, blockIdentifier, leafIdentifier) {
    return harness.send({ operation: 'view.attach', blockIdentifier, leafIdentifier, isEmbedded: true, width: 600 });
}

test('two embeds of one base each draw their own view, at once, as copies', async () => {
    const harness = await loaded();
    try {
        const first = plain(await harness.send(openMessage('First', 0, ['Algebra.md'])));
        const second = plain(await harness.send(openMessage('Second', 1, ['Physics.md'])));
        assert.notEqual(first.leafIdentifier, second.leafIdentifier);
        const firstCopy = plain(await attach(harness, 'first-block', first.leafIdentifier));
        const secondCopy = plain(await attach(harness, 'second-block', second.leafIdentifier));
        assert.match(firstCopy.html, /First year, week 1/);
        assert.match(firstCopy.html, /Algebra: Monday/, 'its row\'s note was read before it drew');
        assert.match(secondCopy.html, /Second year, week 1/);
        assert.match(secondCopy.html, /Physics: Tuesday/);
        assert.doesNotMatch(firstCopy.html, /workspace-leaf/, 'only what the plugin drew, not the leaf\'s fixed-height frame');
        // Attaching the second took nothing from the first: both still follow their plugin views.
        const tapped = plain(await harness.send({ operation: 'codeBlock.event', blockIdentifier: 'first-block', eventType: 'tap', elementPath: [0, 1] }));
        assert.match(tapped.html, /First year, week 2/);
        assert.match(plain(await harness.send({ operation: 'codeBlock.event', blockIdentifier: 'second-block', eventType: 'tap', elementPath: [0, 1] })).html, /Second year, week 2/);
    } finally {
        harness.close();
    }
});

test('an embed scrolled away keeps what it shows when it comes back', async () => {
    const harness = await loaded();
    try {
        const opened = plain(await harness.send(openMessage('First', 0, ['Algebra.md'])));
        await attach(harness, 'block', opened.leafIdentifier);
        await harness.send({ operation: 'codeBlock.event', blockIdentifier: 'block', eventType: 'tap', elementPath: [0, 1] });
        await harness.send({ operation: 'codeBlock.release', blockIdentifier: 'block' });
        const again = plain(await attach(harness, 'block-again', opened.leafIdentifier));
        assert.match(again.html, /week 2/, 'the plugin\'s view lived on, so its chosen week did too');
        assert.equal(harness.window.weekTables, 1, 'and no second view was made');
    } finally {
        harness.close();
    }
});

test('a view embedded in a note tells the plugin of a new width, and keeps the size of the next tab apart', async () => {
    const harness = await loaded();
    try {
        const opened = plain(await harness.send(openMessage('First', 0, ['Algebra.md'])));
        await attach(harness, 'block', opened.leafIdentifier);
        const resizesBefore = harness.window.weekTableResizes;
        await harness.send({ operation: 'view.resize', blockIdentifier: 'block', width: 320 });
        assert.equal(harness.window.weekTableResizes, resizesBefore + 1);
        const leaf = harness.app.workspace.getLeafById(opened.leafIdentifier);
        assert.equal(leaf.containerEl.parentElement.style.width, '320px');
        assert.equal(leaf.containerEl.parentElement.style.height, '420px');
        const nextTab = harness.app.workspace.createPluginLeaf('tab');
        assert.equal(nextTab.waitingPlace.style.width, '700px', 'the size the next tab waits at is not the embed\'s');
        assert.equal(nextTab.waitingPlace.style.height, '600px');
    } finally {
        harness.close();
    }
});

test('editing a shown property redraws the view by itself, and its copy reaches Graphite', async () => {
    const harness = await loaded();
    try {
        const opened = plain(await harness.send(openMessage('First', 0, ['Algebra.md'])));
        await attach(harness, 'block', opened.leafIdentifier);
        harness.writeVaultFile('Algebra.md', '---\nday: Friday\n---\n');
        await harness.send({ operation: 'vault.changes', changes: [{ path: 'Algebra.md', isReloadNeeded: true }] });
        await settle(); await new Promise((resolve) => setTimeout(resolve, 260));
        const copies = plain(harness.host.notificationsOf('codeBlock.changed'));
        assert.match(copies.at(-1).html, /Algebra: Friday/, 'before, the view kept Monday until it was closed and opened again');
    } finally {
        harness.close();
    }
});

test('a view opened while its rows cannot be read yet fills in by itself when they can', async () => {
    const harness = await loaded();
    try {
        harness.host.notDownloadedPaths.add('Algebra.md');
        const opened = plain(await harness.send(openMessage('First', 0, ['Algebra.md'])));
        const copy = plain(await attach(harness, 'block', opened.leafIdentifier));
        assert.match(copy.html, /Algebra: Missing/);
        harness.host.notDownloadedPaths.delete('Algebra.md');
        await harness.send({ operation: 'vault.changes', changes: [{ path: 'Algebra.md', isReloadNeeded: true }] });
        await settle(); await new Promise((resolve) => setTimeout(resolve, 260));
        assert.match(plain(harness.host.notificationsOf('codeBlock.changed')).at(-1).html, /Algebra: Monday/);
    } finally {
        harness.close();
    }
});

test('an opening Graphite gave up on leaves no view behind, whichever comes first', async () => {
    const harness = await loaded();
    try {
        const leavesBefore = harness.app.workspace.pluginLeaves.length;
        // Given up after the answer was on its way.
        const late = plain(await harness.send(Object.assign(openMessage('First', 0, ['Algebra.md']), { openingIdentifier: 'late' })));
        assert.equal(late.isOpened, true);
        await harness.send({ operation: 'basesView.abandonOpening', openingIdentifier: 'late' });
        assert.equal(harness.app.workspace.pluginLeaves.length, leavesBefore);
        // Given up before the plugin was done.
        await harness.send({ operation: 'basesView.abandonOpening', openingIdentifier: 'early' });
        const early = plain(await harness.send(Object.assign(openMessage('First', 0, ['Algebra.md']), { openingIdentifier: 'early' })));
        assert.equal(early.isOpened, false);
        assert.equal(harness.app.workspace.pluginLeaves.length, leavesBefore);
    } finally {
        harness.close();
    }
});

test('Graphite is told each view type\'s icon and options, flattened to what it can show', async () => {
    const harness = await loaded();
    try {
        const view = plain(harness.host.notificationsOf('basesViews.changed').at(-1).views[0]);
        assert.equal(view.icon, 'calendar-days');
        assert.deepEqual(view.options, [
            { key: 'title', type: 'text', displayName: 'Heading', defaultValue: 'A week' },
            { key: 'firstHour', type: 'slider', displayName: 'First hour', defaultValue: 8, min: 6, max: 12, step: 1 },
            { key: 'layout', type: 'dropdown', displayName: 'Layout', choices: [{ value: 'compact', title: 'Compact' }, { value: 'roomy', title: 'Roomy' }] },
        ]);
    } finally {
        harness.close();
    }
});

test('a plugin that sets an option asks Graphite to save it; a code block\'s base stays in memory', async () => {
    const harness = await loaded();
    try {
        const opened = plain(await harness.send(openMessage('First', 0, ['Algebra.md'])));
        const view = harness.app.workspace.getLeafById(opened.leafIdentifier).view.basesView;
        view.config.set('title', 'Changed');
        view.config.set('title', 'Changed');
        const saves = plain(harness.host.notificationsOf('basesView.setOption'));
        assert.deepEqual(saves.map((save) => [save.baseFilePath, save.viewName, save.viewIndex, save.key, save.value]), [['Plan.base', 'First', 0, 'title', 'Changed']], 'once, for the change');
        assert.equal(view.config.get('title'), 'Changed');

        const inline = plain(await harness.send({ operation: 'basesView.open', viewType: 'week-table', viewName: 'Only', viewIndex: 0, baseYaml: 'views:\n  - type: week-table\n    name: Only\n    title: Inline\n', groups: [], properties: [] }));
        harness.app.workspace.getLeafById(inline.leafIdentifier).view.basesView.config.set('title', 'Other');
        assert.equal(plain(harness.host.notificationsOf('basesView.setOption')).length, 1);
    } finally {
        harness.close();
    }
});

test('the view reads new settings when the base file changed them', async () => {
    const harness = await loaded();
    try {
        const opened = plain(await harness.send(openMessage('First', 0, ['Algebra.md'])));
        harness.writeVaultFile('Plan.base', baseText.replace('First year', 'New heading'));
        await harness.send({ operation: 'basesView.update', leafIdentifier: opened.leafIdentifier, viewOptionsChanged: true, groups: [{ key: null, paths: ['Algebra.md'] }], properties: ['note.day'] });
        const content = harness.app.workspace.getLeafById(opened.leafIdentifier).view.contentEl;
        assert.match(content.textContent, /New heading/);
    } finally {
        harness.close();
    }
});

test('values read as in Obsidian: times are kept, declared text stays text, objects print as objects, display names and summaries arrive', async () => {
    const harness = await startRuntime({ files: {
        'Plan.base': 'properties:\n  note.day:\n    displayName: Weekday\nviews:\n  - type: week-table\n    name: First\n',
        '.obsidian/types.json': '{"types":{"code":"text"}}',
        'Note.md': '---\nstart: 2026-09-21T10:15\nday: 2026-09-21\ncode: 2026-09-21\nplace:\n  room: A1\n  floor: 2\n---\n',
    } });
    try {
        await installAndLoadPlugin(harness, { manifest, mainSource: weekTablePlugin });
        await settle();
        const opened = plain(await harness.send(Object.assign(openMessage('First', 0, ['Note.md']), { summaryValues: { 'note.day': { type: 'number', value: 3 } } })));
        const view = harness.app.workspace.getLeafById(opened.leafIdentifier).view.basesView;
        const entry = view.data.data[0];
        const { DateValue, StringValue, ObjectValue } = harness.obsidian;
        assert.equal(entry.getValue('note.start').toString(), '2026-09-21 10:15');
        assert.equal(entry.getValue('note.day').toString(), '2026-09-21');
        assert.ok(entry.getValue('note.day') instanceof DateValue);
        assert.ok(entry.getValue('note.code') instanceof StringValue, 'a property the vault declares as text is text');
        assert.ok(entry.getValue('note.place') instanceof ObjectValue);
        assert.equal(entry.getValue('note.place').toString(), '{"room":"A1","floor":2}');
        assert.equal(view.config.getDisplayName('note.day'), 'Weekday');
        assert.equal(view.config.getDisplayName('note.start'), 'start');
        assert.equal(view.data.getSummaryValue(null, [], 'note.day').toString(), '3');
        assert.equal(view.data.getSummaryValue(null, [], 'note.start').toString(), '');
        await harness.send({ operation: 'basesView.update', leafIdentifier: opened.leafIdentifier, groups: [{ key: null, paths: ['Note.md'] }], properties: ['formula.when', 'formula.pair'],
            formulaValues: { 'Note.md': { 'formula.when': { type: 'date', value: Date.UTC(2026, 8, 21), hasTime: false }, 'formula.pair': { type: 'object', value: [['a', { type: 'number', value: 1 }]] } } } });
        const updated = view.data.data[0];
        assert.equal(updated.getValue('formula.pair').toString(), '{"a":1}');
        assert.match(updated.getValue('formula.when').toString(), /^\d{4}-\d{2}-\d{2}$/);
        assert.equal(view.config.getEvaluatedFormula().toString(), '');
        assert.ok(plain(harness.host.notificationsOf('plugin.unsupportedFeature')).some((report) => report.featureName === 'BasesViewConfig.getEvaluatedFormula'), 'said rather than silently empty');
    } finally {
        harness.close();
    }
});
