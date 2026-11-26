/**
 * File: meta-bind.test.js
 * -----------------------
 * Layer: Tests
 * Description: Meta Bind 1.5.1, unmodified: its buttons, their actions, its input fields and views,
 *              and the course page demo, drawn and pressed as Graphite's reading view does.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

// Meta Bind's release files, pinned by checksum in compatibility-plugins.json, run in the runtime
// with the plugins its actions call (Templater for notes from templates, Obsidian's sample plugin
// for a command). Each note is drawn block by block as the reading view asks for it, and each
// button is pressed by its label through the copy's element path, so these are the steps a person
// takes in Graphite. What is checked is the vault's files and the notes Graphite is asked to open.
// Skipped when Meta Bind is not downloaded (npm run build-compatibility-plugins).
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fileSystem = require('node:fs');
const path = require('node:path');
const { plain, settle, waitUntil } = require('../support/runtime-harness');
const metaBind = require('../support/meta-bind-driver');

const skip = metaBind.builtPlugin(metaBind.metaBindIdentifier) ? false : 'Meta Bind is not downloaded (npm run build-compatibility-plugins)';
const skipWithTemplater = skip || (metaBind.builtPlugin('templater-obsidian') ? false : 'Templater is not built (npm run build-compatibility-plugins)');
const skipWithSamplePlugin = skip || (metaBind.builtPlugin('sample-plugin') ? false : 'The sample plugin is not built (npm run build-compatibility-plugins)');

function buttonBlock(yaml) {
    return '```meta-bind-button\n' + yaml.trim() + '\n```';
}

/// A note of several buttons, one per action, each acting on the note or the vault.
function actionsNote() {
    return [
        '---', 'status: todo', '---', '# Week TODO', '',
        buttonBlock('label: Run the sample command\nstyle: default\naction:\n  type: command\n  command: sample-plugin:open-modal-simple'), '',
        buttonBlock('label: Open the syllabus\nstyle: default\naction:\n  type: open\n  link: "[[Syllabus]]"'), '',
        buttonBlock('label: Open the course site\nstyle: default\naction:\n  type: open\n  link: https://example.com/course'), '',
        buttonBlock('label: New idea\nstyle: default\naction:\n  type: createNote\n  folderPath: Inbox\n  fileName: Idea\n  openNote: true'), '',
        buttonBlock('label: New assignment\nstyle: primary\naction:\n  type: templaterCreateNote\n  templateFile: Templates/Assignment.md\n  folderPath: Assignments\n  fileName: Assignment\n  openNote: true'), '',
        buttonBlock('label: Mark done\nstyle: default\naction:\n  type: updateMetadata\n  bindTarget: status\n  evaluate: false\n  value: done'), '',
        buttonBlock('label: Wait then mark later\nstyle: default\nactions:\n  - type: sleep\n    ms: 200\n  - type: updateMetadata\n    bindTarget: status\n    evaluate: false\n    value: later'), '',
        buttonBlock('label: Add a line\nstyle: default\naction:\n  type: insertIntoNote\n  line: 5\n  value: "Added by the button."'), '',
        buttonBlock('label: Rename the heading\nstyle: default\naction:\n  type: replaceInNote\n  fromLine: 4\n  toLine: 4\n  replacement: "# Week one"'), '',
        buttonBlock('label: Tick the to-dos\nstyle: default\naction:\n  type: regexpReplaceInNote\n  regexp: "- \\\\[ \\\\]"\n  replacement: "- [x]"'), '',
        '- [ ] Read chapter 1', '- [ ] Watch lecture 1', '',
        buttonBlock('label: Replace me\nstyle: default\naction:\n  type: replaceSelf\n  replacement: "The button was here."'), '',
        buttonBlock('label: Run JavaScript\nstyle: default\naction:\n  type: inlineJS\n  code: "console.log(1)"'), '',
    ].join('\n');
}

const actionsVault = () => ({
    'Week.md': actionsNote(),
    'Syllabus.md': '# Syllabus\n',
    'Assignments/Problem set 1.md': '# Problem set 1\n',
    'Templates/Assignment.md': '---\ntype: assignment\ndue: <% tp.date.now("YYYY-MM-DD", 7) %>\n---\n# <% tp.file.title %>\n',
});

async function pressAndWait(harness, blocks, label) {
    const answer = await metaBind.pressButton(harness, blocks, label);
    assert.equal(answer.isHandled, true, label + ' was not pressed');
    for (let round = 0; round < 25; round++) await settle();
}

test('Meta Bind 1.5.1 loads with its blocks and post-processor, and reports only what Graphite lacks', { skip }, async () => {
    const { harness, answers } = await metaBind.startWithMetaBind({ files: { 'Note.md': '# Note\n' }, notePath: 'Note.md' });
    try {
        assert.deepEqual(answers, { 'obsidian-meta-bind-plugin': { isLoaded: true } });
        const languages = plain(harness.host.notificationsOf('codeBlocks.changed').at(-1)).languages;
        for (const language of ['meta-bind', 'meta-bind-button', 'meta-bind-embed', 'meta-bind-js-view']) assert.ok(languages.includes(language), language);
        assert.deepEqual(plain(harness.host.notificationsOf('postProcessors.changed').at(-1)).pluginIdentifiers, ['obsidian-meta-bind-plugin']);
        const commandNames = plain(harness.host.notificationsOf('commands.changed').at(-1).commands.map((command) => command.name));
        assert.ok(commandNames.includes('Meta Bind: Open button builder'), commandNames.join(', '));
        // Its inline fields in Live Preview are CodeMirror widgets, which Graphite's native editor
        // does not run; its highlighting of its own syntax is a CodeMirror 5 mode; Prism is
        // Obsidian's copy of a library Graphite does not ship.
        assert.deepEqual(plain(harness.host.notificationsOf('plugin.unsupportedFeature').map((notification) => notification.featureName)).sort(),
            ['CodeMirror editor extensions', 'Syntax highlighting modes (CodeMirror 5)']);
        const drawn = plain(await harness.send({ operation: 'codeBlock.render', blockIdentifier: 'button', language: 'meta-bind-button', source: 'label: Hello\nstyle: primary\nactions: []', sourcePath: 'Note.md', width: 600 }));
        assert.match(drawn.html, /<button class="mb-button-inner mod-cta"[^>]*>.*Hello<\/button>/);
        assert.ok(plain(harness.host.notificationsOf('plugin.unsupportedFeature')).some((notification) => notification.featureName === 'loadPrism'));
        assert.deepEqual(metaBind.pageErrors(harness), []);
    } finally {
        harness.close();
    }
});

test('Meta Bind\'s buttons run commands, open notes and web pages, and create notes, from templates too', { skip: skipWithTemplater || skipWithSamplePlugin }, async () => {
    const { harness } = await metaBind.startWithMetaBind({ files: actionsVault(), notePath: 'Week.md', otherPlugins: ['sample-plugin', 'templater-obsidian'], pluginData: { 'templater-obsidian': { templates_folder: 'Templates' } } });
    try {
        const blocks = await metaBind.drawNote(harness, 'Week.md');

        await pressAndWait(harness, blocks, 'Run the sample command');
        assert.equal(harness.window.document.querySelector('.modal-container .modal-content').textContent, 'Woah!', 'the sample plugin\'s command opened its window');
        assert.equal(plain(harness.host.notificationsOf('surface.present')).length, 1);

        await pressAndWait(harness, blocks, 'Open the syllabus');
        await pressAndWait(harness, blocks, 'Open the course site');
        assert.deepEqual(plain(harness.host.notificationsOf('workspace.openExternalLink').map((notification) => notification.address)), ['https://example.com/course']);

        await pressAndWait(harness, blocks, 'New idea');
        assert.equal(harness.readVaultFile('Inbox/Idea.md'), '', 'createNote makes an empty note, as in Obsidian');

        await pressAndWait(harness, blocks, 'New assignment');
        await pressAndWait(harness, blocks, 'New assignment');
        const due = harness.window.moment().add(7, 'days').format('YYYY-MM-DD');
        assert.equal(harness.readVaultFile('Assignments/Assignment.md'), '---\ntype: assignment\ndue: ' + due + '\n---\n# Assignment\n');
        assert.equal(harness.readVaultFile('Assignments/Assignment 1.md'), '---\ntype: assignment\ndue: ' + due + '\n---\n# Assignment 1\n', 'a second press makes the next name');

        assert.deepEqual(plain(harness.host.openedFiles.map((request) => request.resolvedPath || request.path)),
            ['Syllabus.md', 'Inbox/Idea.md', 'Assignments/Assignment.md', 'Assignments/Assignment 1.md']);
        assert.deepEqual(metaBind.pageErrors(harness), []);
    } finally {
        harness.close();
    }
});

test('Meta Bind\'s buttons set properties and edit their note: one after another, the note keeps every change', { skip }, async () => {
    const { harness } = await metaBind.startWithMetaBind({ files: actionsVault(), notePath: 'Week.md' });
    try {
        const blocks = await metaBind.drawNote(harness, 'Week.md');
        await pressAndWait(harness, blocks, 'Mark done');
        await metaBind.waitForMetaBindWrites();
        assert.equal(metaBind.frontmatterOf(harness, 'Week.md').status, 'done');
        await pressAndWait(harness, blocks, 'Wait then mark later');
        await metaBind.waitForMetaBindWrites();
        assert.equal(metaBind.frontmatterOf(harness, 'Week.md').status, 'later', 'the second action ran after the first');

        await pressAndWait(harness, blocks, 'Add a line');
        await pressAndWait(harness, blocks, 'Rename the heading');
        await pressAndWait(harness, blocks, 'Tick the to-dos');
        await pressAndWait(harness, blocks, 'Replace me');
        const text = harness.readVaultFile('Week.md');
        assert.match(text, /^---\nstatus: later\n---\n# Week one\nAdded by the button\.\n\n```meta-bind-button\n/);
        assert.match(text, /\n- \[x\] Read chapter 1\n- \[x\] Watch lecture 1\n/);
        assert.match(text, /\nThe button was here\.\n/);
        assert.doesNotMatch(text, /label: Replace me/);

        // JavaScript actions need Meta Bind's "Enable JavaScript" setting and the JS Engine plugin,
        // as in Obsidian; off by default, Meta Bind says so and changes nothing.
        await pressAndWait(harness, blocks, 'Run JavaScript');
        assert.equal(harness.readVaultFile('Week.md'), text);
        assert.match(metaBind.pageErrors(harness).join('\n'), /JS evaluation is disabled in the plugin settings/);
        assert.equal(plain(harness.host.notificationsOf('notice.show')).at(-1).message, 'meta-bind | Error while running button action. Check the console for details.');
    } finally {
        harness.close();
    }
});

test('Meta Bind\'s inline buttons come from a hidden button of the note and from its button templates', { skip }, async () => {
    const note = [
        '---', 'status: todo', '---', '# Page', '',
        'Here: `BUTTON[mark-done, mark-later]`', '',
        buttonBlock('label: Mark done\nid: mark-done\nhidden: true\nstyle: primary\naction:\n  type: updateMetadata\n  bindTarget: status\n  evaluate: false\n  value: done'), '',
    ].join('\n');
    const template = { label: 'Mark later', id: 'mark-later', style: 'default', action: { type: 'updateMetadata', bindTarget: 'status', evaluate: false, value: 'later' } };
    const { harness } = await metaBind.startWithMetaBind({ files: { 'Page.md': note }, notePath: 'Page.md', pluginData: { 'obsidian-meta-bind-plugin': { buttonTemplates: [template] } } });
    try {
        const blocks = await metaBind.drawNote(harness, 'Page.md');
        const hidden = blocks.find((block) => block.kind === 'codeBlock');
        assert.equal(metaBind.currentHTML(harness, hidden), '<div class="mb-button mb-button-block"></div>', 'a hidden button draws nothing');
        // The inline buttons were drawn before the hidden block registered its button: Meta Bind
        // waits for it, and the copy is sent again once it is there.
        await waitUntil(() => metaBind.findInBlocks(harness, blocks, 'button.mb-button-inner', 'Mark done'));
        assert.ok(metaBind.findInBlocks(harness, blocks, 'button.mb-button-inner', 'Mark later'));
        await pressAndWait(harness, blocks, 'Mark done');
        await metaBind.waitForMetaBindWrites();
        assert.equal(metaBind.frontmatterOf(harness, 'Page.md').status, 'done');
        await new Promise((resolve) => setTimeout(resolve, 1100));
        await pressAndWait(harness, blocks, 'Mark later');
        await metaBind.waitForMetaBindWrites();
        assert.equal(metaBind.frontmatterOf(harness, 'Page.md').status, 'later');
        assert.deepEqual(metaBind.pageErrors(harness), []);
    } finally {
        harness.close();
    }
});

test('Meta Bind\'s input fields write the note\'s properties, and show a property changed elsewhere', { skip }, async () => {
    const note = [
        '---', 'title: Signals', 'credits: 4', 'status: todo', 'effort: 2', 'lectures: 3', '---', '# Course', '',
        'Done `INPUT[toggle:finished]`', '',
        'Title `INPUT[text:title]`', '',
        'Credits `INPUT[number:credits]`', '',
        'Exam `INPUT[date:exam]`', '',
        'Status `INPUT[inlineSelect(option(todo), option(doing), option(done)):status]`', '',
        'Effort `INPUT[slider(minValue(0), maxValue(10)):effort]`', '',
        'Room `INPUT[suggester(option(BC 01), option(CE 1 4)):room]`', '',
        'Twice the credits: `VIEW[{credits} * 2][math]`, title: `VIEW[{title}][text]`', '',
        '```meta-bind', 'INPUT[progressBar(minValue(0), maxValue(14)):lectures]', '```', '',
        '```meta-bind', 'INPUT[list:topics]', '```', '',
    ].join('\n');
    const { harness } = await metaBind.startWithMetaBind({ files: { 'Course.md': note }, notePath: 'Course.md' });
    try {
        const blocks = await metaBind.drawNote(harness, 'Course.md');
        const view = blocks.find((block) => block.source.startsWith('Twice'));
        assert.match(metaBind.currentHTML(harness, view), /mb-view-type-math">8</);
        assert.match(metaBind.currentHTML(harness, view), /mb-view-type-text">Signals</);
        assert.match(metaBind.currentHTML(harness, blocks.find((block) => block.source.includes('progressBar'))), /mb-input-type-progressBar/);
        assert.match(metaBind.currentHTML(harness, blocks.find((block) => block.source.includes('list:topics'))), /mb-input-type-list/);

        const toggle = metaBind.findInBlocks(harness, blocks, '.mb-input-type-toggle .checkbox-container');
        assert.equal(plain(await harness.send({ operation: 'codeBlock.event', blockIdentifier: toggle.block.blockIdentifier, elementPath: toggle.elementPath })).isHandled, true);
        await metaBind.enterInField(harness, blocks, 'text', 'input', 'Signals and Systems');
        await metaBind.enterInField(harness, blocks, 'number', 'input', '6');
        await metaBind.enterInField(harness, blocks, 'date', 'input', '2027-01-20');
        await metaBind.enterInField(harness, blocks, 'inlineSelect', 'select', 'doing');
        await metaBind.enterInField(harness, blocks, 'slider', 'input', '7');
        const suggester = metaBind.findInBlocks(harness, blocks, '.mb-input-type-suggester button');
        await harness.send({ operation: 'codeBlock.event', blockIdentifier: suggester.block.blockIdentifier, elementPath: suggester.elementPath });
        await waitUntil(() => harness.window.document.querySelector('.modal-container .suggestion-item'));
        harness.window.document.querySelector('.modal-container .suggestion-item').click();
        await metaBind.waitForMetaBindWrites();
        assert.deepEqual(metaBind.frontmatterOf(harness, 'Course.md'),
            { title: 'Signals and Systems', credits: 6, status: 'doing', effort: 7, lectures: 3, finished: true, exam: '2027-01-20', room: 'BC 01' });
        assert.match(metaBind.currentHTML(harness, view), /mb-view-type-math">12</, 'the view follows the field');

        // Meta Bind ignores the note's changes for a second after its own write, so that it does not
        // read back what it wrote; then another app's edit reaches every field and view.
        await new Promise((resolve) => setTimeout(resolve, 1100));
        harness.writeVaultFile('Course.md', harness.readVaultFile('Course.md').replace('credits: 6', 'credits: 9').replace('status: doing', 'status: done'));
        await harness.send({ operation: 'vault.changes', changes: [{ path: 'Course.md', isReloadNeeded: true }] });
        await waitUntil(() => /mb-view-type-math">18</.test(metaBind.currentHTML(harness, view)), 3000);
        assert.match(metaBind.currentHTML(harness, metaBind.findInBlocks(harness, blocks, '.mb-input-type-number').block), /value="9"/);
        assert.match(metaBind.currentHTML(harness, metaBind.findInBlocks(harness, blocks, '.mb-input-type-inlineSelect').block), /<option value="done" selected="">/);
        assert.deepEqual(metaBind.pageErrors(harness), []);
    } finally {
        harness.close();
    }
});

test('the course page demo: New assignment and Start lecture, Meta Bind\'s button templates, make their notes from templates, and the page follows', { skip: skipWithTemplater }, async () => {
    const coursePath = 'Signals and Systems/Signals and Systems.md';
    const files = metaBind.vaultFilesInFolder(path.join(__dirname, '..', 'fixtures', 'meta-bind-course-vault'));
    const { harness, answers } = await metaBind.startWithMetaBind({ files, notePath: coursePath, otherPlugins: ['templater-obsidian'] });
    try {
        assert.deepEqual(answers, { 'templater-obsidian': { isLoaded: true }, 'obsidian-meta-bind-plugin': { isLoaded: true } });
        const blocks = await metaBind.drawNote(harness, coursePath);
        await waitUntil(() => metaBind.findInBlocks(harness, blocks, 'button.mb-button-inner', 'Start lecture'));
        const progress = blocks.find((block) => block.source.includes('progressBar'));
        assert.match(metaBind.currentHTML(harness, progress), /data-internal-value="1"/);

        await pressAndWait(harness, blocks, 'New assignment');
        const due = harness.window.moment().add(7, 'days').format('YYYY-MM-DD');
        assert.equal(harness.readVaultFile('Signals and Systems/Assignments/New assignment.md'), [
            '---', 'course: "[[Signals and Systems]]"', 'type: assignment', 'status: To do', 'due: ' + due, '---', '# New assignment', '',
            'Status `INPUT[inlineSelect(option(To do), option(Doing), option(Handed in)):status]` · Due `INPUT[date:due]`', '',
        ].join('\n'));

        await pressAndWait(harness, blocks, 'Start lecture');
        await waitUntil(() => harness.vaultFileExists('Signals and Systems/Lectures/Lecture 2.md'), 3000);
        const today = harness.window.moment().format('YYYY-MM-DD');
        assert.equal(harness.readVaultFile('Signals and Systems/Lectures/Lecture 2.md'),
            '---\ncourse: "[[Signals and Systems]]"\ntype: lecture\nnumber: 2\ndate: ' + today + '\n---\n# Lecture 2\n\n## Notes\n\n');
        assert.equal(metaBind.frontmatterOf(harness, coursePath).lectures_held, 2);
        await waitUntil(() => /data-internal-value="2"/.test(metaBind.currentHTML(harness, progress)), 3000);

        assert.deepEqual(plain(harness.host.openedFiles.map((request) => request.path)),
            ['Signals and Systems/Assignments/New assignment.md', 'Signals and Systems/Lectures/Lecture 2.md']);
        const courseText = harness.readVaultFile(coursePath);
        assert.equal(courseText, files[coursePath].replace('lectures_held: 1', 'lectures_held: 2'), 'the course page changed in that property alone');
        assert.deepEqual(metaBind.pageErrors(harness), []);
    } finally {
        harness.close();
    }
});

test('the course page demo vault holds only what its README describes', () => {
    const folder = path.join(__dirname, '..', 'fixtures', 'meta-bind-course-vault');
    assert.deepEqual(Object.keys(metaBind.vaultFilesInFolder(folder)).sort(), [
        '.obsidian/plugins/obsidian-meta-bind-plugin/data.json',
        '.obsidian/plugins/templater-obsidian/data.json',
        'README.md',
        'Signals and Systems/Assignments/Problem set 1.md',
        'Signals and Systems/Course work.base',
        'Signals and Systems/Lectures/Lecture 1.md',
        'Signals and Systems/Signals and Systems.md',
        'Templates/Assignment.md',
        'Templates/Lecture.md',
    ]);
    for (const pluginIdentifier of ['obsidian-meta-bind-plugin', 'templater-obsidian']) {
        assert.ok(!fileSystem.existsSync(path.join(folder, '.obsidian', 'plugins', pluginIdentifier, 'main.js')), pluginIdentifier + ' is downloaded, never committed: only its settings are');
    }
});
