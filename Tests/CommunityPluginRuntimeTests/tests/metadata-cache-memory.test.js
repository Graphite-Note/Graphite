/**
 * File: metadata-cache-memory.test.js
 * -----------------------------------
 * Layer: Tests
 * Description: The metadata cache keeps a note's metadata without its text: strings cut from the note are copied.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 07/11/2026
 */

// JavaScript engines cut a substring as a view into the string it came from (V8 for 13
// characters or more, JavaScriptCore for most lengths), so a heading kept in the metadata
// would keep its note's whole text alive. These tests parse large notes, drop their text,
// and measure what stays.
'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const v8 = require('node:v8');
const vm = require('node:vm');
const { startRuntime, plain } = require('../support/runtime-harness');

v8.setFlagsFromString('--expose-gc');
const collectGarbage = vm.runInNewContext('gc');

const noteCount = 16;
const noteBytes = 1024 * 1024;

/// Prose of about ten kilobytes, so a paragraph is mostly text the metadata does not keep.
const longProse = 'The spectrum of a sampled signal repeats at every multiple of the sampling frequency. '.repeat(120);

/// A note of about a megabyte whose few kept parts (frontmatter values, headings, links,
/// tags, block identifiers, tasks) are all longer than the engines' substring thresholds.
function largeNote(noteIndex) {
    const lines = [
        '---',
        'course: "Signals and systems, lecture ' + noteIndex + '"',
        'shared: &shared { teacher: "Professor of signal processing ' + noteIndex + '" }',
        'again: *shared',
        '---',
        '# Sampling and reconstruction of signals ' + noteIndex,
        '',
    ];
    let size = lines.join('\n').length;
    for (let paragraphIndex = 0; size < noteBytes; paragraphIndex += 1) {
        const paragraph = paragraphIndex % 20 === 0
            ? '## Section about aliasing number ' + paragraphIndex + '\n\n- [ ] exercise on the Nyquist rate ' + paragraphIndex + ' ^exercise-' + noteIndex + '-' + paragraphIndex
            : longProse + 'See [[Fourier transform properties ' + paragraphIndex + ']] and #signals/sampling-theory-' + paragraphIndex + '.';
        lines.push(paragraph, '');
        size += paragraph.length + 2;
    }
    return lines.join('\n');
}

function heapUsedAfterCollecting() {
    collectGarbage();
    collectGarbage();
    return process.memoryUsage().heapUsed;
}

test('the metadata of parsed notes does not keep their text alive', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const NoteParser = harness.runtime.NoteParser;
        const keptMetadata = [];
        const heapBefore = heapUsedAfterCollecting();
        let firstNoteText = null;
        for (let noteIndex = 0; noteIndex < noteCount; noteIndex += 1) {
            const text = largeNote(noteIndex);
            if (noteIndex === 0) firstNoteText = text.slice(0, 400);
            keptMetadata.push(new NoteParser(text).parse());
        }
        const keptBytes = heapUsedAfterCollecting() - heapBefore;
        const textBytes = noteCount * noteBytes;
        // The metadata itself is a few megabytes; with the texts it would be over 16 MB.
        assert.ok(keptBytes < textBytes / 4, 'kept ' + Math.round(keptBytes / 1048576) + ' MB for ' + noteCount + ' notes of 1 MB');

        // The copies hold the same characters, and frontmatter that shares an object (a YAML
        // alias) still shares it.
        const first = keptMetadata[0];
        assert.equal(first.headings[0].heading, 'Sampling and reconstruction of signals 0');
        assert.equal(first.frontmatter.course, 'Signals and systems, lecture 0');
        assert.equal(first.frontmatter.again, first.frontmatter.shared);
        assert.equal(first.frontmatter.shared.teacher, 'Professor of signal processing 0');
        assert.equal(first.links[0].link, 'Fourier transform properties 1');
        assert.equal(first.tags[0].tag, '#signals/sampling-theory-1');
        assert.ok(firstNoteText.includes(first.headings[0].heading));
    } finally {
        harness.close();
    }
});

test('copied strings keep characters outside Latin-1 and lone surrogates as they were', async () => {
    const harness = await startRuntime({ files: {} });
    try {
        const heading = 'Fourier → Laplace — 𝔼[x] \uD800 end';
        const metadata = plain(new harness.runtime.NoteParser('# ' + heading + '\n\nSee [[Café → menu]] and #théorie\n').parse());
        // `plain` would turn a lone surrogate into its escape and back, so compare the parser's own value too.
        const own = new harness.runtime.NoteParser('# ' + heading + '\n').parse();
        assert.equal(own.headings[0].heading, heading);
        assert.equal(metadata.links[0].link, 'Café → menu');
        assert.equal(metadata.tags[0].tag, '#théorie');
    } finally {
        harness.close();
    }
});
