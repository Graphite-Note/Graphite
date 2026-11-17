/**
 * File: notion-export-fixture.js
 * ------------------------------
 * Layer: Tests
 * Description: Makes up Notion HTML exports, as zips, for the Notion import tests.
 *
 * Authors: Bahey Shalash
 * Version: 1.0
 * Date: 17/11/2026
 */

// A Notion workspace's HTML export, made up for the tests: nobody's notes, only invented course
// notes. The markup is the export's own, as Obsidian's Importer reads it (pages are `article`s with
// an id, a `header` with the title and a property table, and a `div.page-body`; subpages are in a
// folder named like their parent's file; attachments are in their page's folder, linked with
// percent-encoded paths). Each page's id is made from its place in the workspace, so the same
// export comes out every time and the expected import can be committed beside the tests.
//
// The zip is the one Notion hands out: `Export-<id>.zip`, holding `Export-<id>-Part-N.zip` files,
// each with the part's pages under the `Export-<id>/` folder.
'use strict';

const crypto = require('node:crypto');
const zlib = require('node:zlib');

const exportIdentifier = '6b1d2c3e-4f50-4a61-8b72-93a4b5c6d7e8';

/// A 32-character Notion id made from a page's place in the workspace.
function notionIdentifier(placeName) {
    return crypto.createHash('sha256').update(placeName).digest('hex').slice(0, 32);
}

/// The id as Notion writes it in an `id` attribute: dashed like a UUID.
function dashedIdentifier(identifier) {
    return [identifier.slice(0, 8), identifier.slice(8, 12), identifier.slice(12, 16), identifier.slice(16, 20), identifier.slice(20)].join('-');
}

function escapedText(text) {
    return String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

/// A relative path as the export links it: each part percent-encoded, slashes kept.
function linkedPath(relativePath) {
    return relativePath.split('/').map((part) => encodeURIComponent(part)).join('/');
}

/// Notion shortens file names and drops the characters a file cannot have; the page's full
/// title stays in its `title` element, which Importer reads.
function exportedFileTitle(title) {
    return title.replace(/[/\\:*?"<>|]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 50).trim() || 'Untitled';
}

function pageDocument(page, bodyMarkup) {
    const propertyRows = (page.properties || []).map((property) => '<tr class="property-row property-row-' + property.type + '"><th>'
        + '<span class="icon property-icon"></span>' + escapedText(property.name) + '</th><td>' + property.markup + '</td></tr>').join('');
    const propertyTable = propertyRows ? '<table class="properties"><tbody>' + propertyRows + '</tbody></table>' : '';
    return '<html><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8"/><title>' + escapedText(page.title)
        + '</title><style>body { white-space: pre-wrap; }</style></head><body><article id="' + dashedIdentifier(page.identifier)
        + '" class="page sans"><header><h1 class="page-title">' + escapedText(page.title) + '</h1><p class="page-description"></p>'
        + propertyTable + '</header><div class="page-body">' + bodyMarkup + '</div></article>'
        + '<span class="sans" style="font-size:14px;padding-top:2em"></span></body></html>';
}

/// Adds a page under `parent` (or at the top), with its file and folder names as the export makes them.
function addPage(workspace, parent, title, makeBody, properties) {
    const identifier = notionIdentifier((parent ? parent.identifier : 'workspace') + '/' + title + '/' + workspace.pages.length);
    const fileStem = exportedFileTitle(title) + ' ' + identifier;
    const folder = parent ? parent.childFolder : '';
    const page = { identifier, title, properties, parent, folder, fileStem, childFolder: folder + fileStem + '/', makeBody, children: [] };
    if (parent) parent.children.push(page);
    workspace.pages.push(page);
    return page;
}

/// A link from `fromPage`'s file to `toPage`'s, as the export writes it.
function relativeLink(fromPage, toPage) {
    const fromParts = fromPage.folder.split('/').filter(Boolean);
    const toPath = toPage.folder + toPage.fileStem + '.html';
    let sharedCount = 0;
    while (sharedCount < fromParts.length && toPath.startsWith(fromParts.slice(0, sharedCount + 1).join('/') + '/')) sharedCount += 1;
    const upward = '../'.repeat(fromParts.length - sharedCount);
    return upward + linkedPath(toPath.split('/').slice(sharedCount).join('/'));
}

function attachmentLink(page, fileName) {
    return linkedPath(page.fileStem + '/' + fileName);
}

function linkToPage(fromPage, toPage) {
    return '<figure id="' + dashedIdentifier(toPage.identifier) + '" class="link-to-page"><a href="' + relativeLink(fromPage, toPage) + '">'
        + escapedText(toPage.title) + '</a></figure>';
}

function paragraph(markup, identifier) {
    return '<p id="' + dashedIdentifier(notionIdentifier(identifier)) + '" class="">' + markup + '</p>';
}

/// A one-pixel PNG, and a PDF with one empty page: real files of their kind, made up here.
const pixelImage = Buffer.from('89504e470d0a1a0a0000000d4948445200000001000000010806000000'
    + '1f15c4890000000d4944415478da63f8cf00000301010018dd8db00000000049454e44ae426082', 'hex');
const emptyDocument = Buffer.from('%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n'
    + '3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n');

/// The small workspace: two courses' notes with every block the HTML export writes that Importer
/// converts, a database of lectures, pages nested five deep, odd titles and attachments.
function makeSmallWorkspace() {
    const workspace = { pages: [], attachments: [] };
    const home = addPage(workspace, null, 'Study Notes', (page) => paragraph('Notes for two made-up courses.', 'home-intro')
        + page.children.map((child) => linkToPage(page, child)).join(''));
    const signals = addPage(workspace, home, 'Signals and Systems', (page) => [
        '<h1 id="' + dashedIdentifier(notionIdentifier('signals-h1')) + '" class="">Fourier series</h1>',
        paragraph('A periodic signal is a sum of sines: <strong>bold</strong>, <em>italic</em>, <code>inline code</code>, '
            + '<mark class="highlight-yellow">highlighted</mark> and <del>struck</del>.', 'signals-p1'),
        paragraph('Inline math: <span class="notion-text-equation-token" contenteditable="false"><span class="katex"><span class="katex-mathml">'
            + '<math><semantics><annotation encoding="application/x-tex">x(t) = \\sum_k a_k e^{jk\\omega_0 t}</annotation></semantics></math>'
            + '</span></span></span> for every t.', 'signals-p2'),
        '<figure id="' + dashedIdentifier(notionIdentifier('signals-equation')) + '" class="equation"><div class="equation-container">'
            + '<span class="katex-display"><span class="katex"><span class="katex-mathml"><math display="block"><semantics>'
            + '<annotation encoding="application/x-tex">a_k = \\frac{1}{T} \\int_T x(t) e^{-jk\\omega_0 t} \\, dt</annotation>'
            + '</semantics></math></span></span></span></div></figure>',
        '<figure class="block-color-gray_background callout" style="white-space:pre-wrap;display:flex" id="'
            + dashedIdentifier(notionIdentifier('signals-callout')) + '"><div style="font-size:1.5em"><span class="icon">💡</span></div>'
            + '<div style="width:100%">'
            + paragraph('Remember: the coefficients of a real signal are conjugate symmetric.', 'signals-callout-p') + '</div></figure>',
        '<ul id="' + dashedIdentifier(notionIdentifier('signals-toggle')) + '" class="toggle"><li><details open=""><summary>Why does it converge?</summary>'
            + paragraph('Because the signal has finite energy over a period.', 'signals-toggle-p') + '</details></li></ul>',
        '<details open=""><summary style="font-weight:600;font-size:1.5em;line-height:1.3;margin:0">Worked example</summary><div class="indented">'
            + paragraph('A square wave has only odd harmonics.', 'signals-toggle-heading-p') + '</div></details>',
        '<pre id="' + dashedIdentifier(notionIdentifier('signals-code')) + '" class="code"><code class="language-Python">import numpy\n'
            + 'coefficients = numpy.fft.fft(samples) / len(samples)</code></pre>',
        '<ul id="' + dashedIdentifier(notionIdentifier('signals-todo')) + '" class="to-do-list"><li><div class="checkbox checkbox-on"></div> '
            + '<span class="to-do-children-checked">Read chapter 3</span><div class="indented"></div></li></ul>',
        '<ul id="' + dashedIdentifier(notionIdentifier('signals-list')) + '" class="bulleted-list"><li style="list-style-type:disc">Linear'
            + '<ul class="bulleted-list"><li style="list-style-type:circle">Time invariant</li></ul></li></ul>',
        '<ol type="1" id="' + dashedIdentifier(notionIdentifier('signals-numbered')) + '" class="numbered-list" start="1"><li>Sample</li></ol>'
            + '<ol type="1" id="' + dashedIdentifier(notionIdentifier('signals-numbered-2')) + '" class="numbered-list" start="2"><li>Transform</li></ol>',
        '<blockquote id="' + dashedIdentifier(notionIdentifier('signals-quote')) + '" class="">Everything is a filter.</blockquote>',
        '<hr id="' + dashedIdentifier(notionIdentifier('signals-divider')) + '"/>',
        '<table id="' + dashedIdentifier(notionIdentifier('signals-table')) + '" class="simple-table"><tbody>'
            + '<tr><th class="simple-table-header">Signal</th><th class="simple-table-header">Period</th></tr>'
            + '<tr><td>Square</td><td>T</td></tr><tr><td>Sawtooth</td><td>2T</td></tr></tbody></table>',
        '<figure id="' + dashedIdentifier(notionIdentifier('signals-image')) + '" class="image"><a href="' + attachmentLink(page, 'spectrum plot.png')
            + '"><img style="width:240px" src="' + attachmentLink(page, 'spectrum plot.png') + '"/></a><figcaption>The spectrum</figcaption></figure>',
        '<figure id="' + dashedIdentifier(notionIdentifier('signals-pdf')) + '"><div class="source"><a href="' + attachmentLink(page, 'Problem set 1.pdf')
            + '">Problem set 1.pdf</a></div></figure>',
        '<figure id="' + dashedIdentifier(notionIdentifier('signals-bookmark')) + '"><a href="https://example.com/fourier" class="bookmark source">'
            + '<div class="bookmark-info"><div class="bookmark-text"><div class="bookmark-title">Fourier series notes</div>'
            + '<div class="bookmark-description">An invented reference page.</div></div><div class="bookmark-href">https://example.com/fourier</div>'
            + '</div></a></figure>',
        ...page.children.map((child) => linkToPage(page, child)),
    ].join(''));
    workspace.attachments.push({ page: signals, fileName: 'spectrum plot.png', contents: pixelImage });
    workspace.attachments.push({ page: signals, fileName: 'Problem set 1.pdf', contents: emptyDocument });

    const lectures = addPage(workspace, signals, 'Lectures', (page) => {
        const rows = page.children.map((row) => '<tr id="' + dashedIdentifier(row.identifier) + '"><td class="cell-title"><a href="'
            + relativeLink(page, row) + '">' + escapedText(row.title) + '</a></td><td class="cell-date"><time>' + row.lectureDate + '</time></td>'
            + '<td class="cell-select"><span class="selected-value select-value-color-blue">' + row.lectureStatus + '</span></td></tr>').join('');
        return '<table class="collection-content"><thead><tr><th>Name</th><th>Date</th><th>Status</th></tr></thead><tbody>' + rows + '</tbody></table>';
    });
    const lectureRows = [['Lecture 1: Signals', '@September 9, 2026', 'Done'], ['Lecture 2: Systems', '@September 16, 2026', 'Done'],
        ['Lecture 3: Convolution', '@September 23, 2026', 'To review']];
    for (const [title, lectureDate, lectureStatus] of lectureRows) {
        const row = addPage(workspace, lectures, title, (page) => paragraph('Notes of ' + escapedText(page.title) + '.', title), [
            { type: 'date', name: 'Date', markup: '<time>' + lectureDate + '</time>' },
            { type: 'select', name: 'Status', markup: '<span class="selected-value select-value-color-blue">' + lectureStatus + '</span>' },
            { type: 'multi_select', name: 'Tags', markup: '<span class="selected-value">lecture</span><span class="selected-value">signals</span>' },
            { type: 'checkbox', name: 'Reviewed', markup: '<div class="checkbox checkbox-' + (lectureStatus === 'Done' ? 'on' : 'off') + '"></div>' },
            { type: 'number', name: 'Pages', markup: '12' },
            { type: 'url', name: 'Slides', markup: '<a href="https://example.com/slides" class="url-value">https://example.com/slides</a>' },
            { type: 'created_time', name: 'Created', markup: '<time>@September 1, 2026 8:00 AM</time>' },
            { type: 'last_edited_time', name: 'Last edited', markup: '<time>@October 1, 2026 9:15 AM</time>' },
        ]);
        row.lectureDate = lectureDate;
        row.lectureStatus = lectureStatus;
    }

    let nestingParent = addPage(workspace, home, 'Linear Algebra', (page) => paragraph('Vectors and matrices.', 'algebra')
        + page.children.map((child) => linkToPage(page, child)).join(''));
    for (const depth of [2, 3, 4, 5]) {
        nestingParent = addPage(workspace, nestingParent, 'Depth ' + depth, (page) => paragraph('A page ' + depth + ' levels down.', 'depth-' + depth)
            + page.children.map((child) => linkToPage(page, child)).join(''));
    }
    const oddTitles = addPage(workspace, home, 'Odd titles', (page) => page.children.map((child) => linkToPage(page, child)).join(''));
    for (const title of ['Input/Output: a recap', 'Eigenvalues 🎯', 'Same title', 'Same title', 'A very long title '.repeat(12).trim()]) {
        addPage(workspace, oddTitles, title, (page) => paragraph('The page called ' + escapedText(page.title) + '.', 'odd-' + workspace.pages.length));
    }
    return workspace;
}

/// The large workspace for measuring: `pageCount` pages under ten parents, each a few paragraphs long.
function makeLargeWorkspace(pageCount) {
    const workspace = { pages: [], attachments: [] };
    const home = addPage(workspace, null, 'Large workspace', (page) => page.children.map((child) => linkToPage(page, child)).join(''));
    const parents = Array.from({ length: 10 }, (unused, parentNumber) => addPage(workspace, home, 'Course ' + (parentNumber + 1),
        (page) => page.children.map((child) => linkToPage(page, child)).join('')));
    for (let pageNumber = 1; workspace.pages.length < pageCount; pageNumber += 1) {
        addPage(workspace, parents[pageNumber % parents.length], 'Note ' + pageNumber, (page) => [1, 2, 3].map((paragraphNumber) => paragraph(
            'Paragraph ' + paragraphNumber + ' of note ' + pageNumber + ', with <strong>bold</strong> text and a <code>term</code>.',
            'large-' + pageNumber + '-' + paragraphNumber)).join(''));
    }
    return workspace;
}

/// Every file of the export, as paths inside the `Export-<id>/` folder and their contents.
function exportFiles(workspace) {
    const files = workspace.pages.map((page) => ({
        path: page.folder + page.fileStem + '.html',
        contents: Buffer.from(pageDocument(page, page.makeBody(page))),
    }));
    for (const attachment of workspace.attachments) files.push({ path: attachment.page.childFolder + attachment.fileName, contents: attachment.contents });
    files.push({ path: 'index.html', contents: Buffer.from('<html><body><p>Export summary</p></body></html>') });
    return files;
}

const fixedModificationTime = { dosTime: (10 << 11) | (30 << 5), dosDate: ((2026 - 1980) << 9) | (11 << 5) | 16 };

/// A zip of `entries` (`{ path, contents }`), stored without compression, with UTF-8 names.
function zipArchive(entries) {
    const localParts = [];
    const centralParts = [];
    let offset = 0;
    for (const entry of entries) {
        const name = Buffer.from(entry.path, 'utf8');
        const checksum = zlib.crc32(entry.contents);
        const local = Buffer.alloc(30);
        local.writeUInt32LE(0x04034b50, 0);
        local.writeUInt16LE(20, 4);
        local.writeUInt16LE(0x0800, 6);
        local.writeUInt16LE(0, 8);
        local.writeUInt16LE(fixedModificationTime.dosTime, 10);
        local.writeUInt16LE(fixedModificationTime.dosDate, 12);
        local.writeUInt32LE(checksum, 14);
        local.writeUInt32LE(entry.contents.length, 18);
        local.writeUInt32LE(entry.contents.length, 22);
        local.writeUInt16LE(name.length, 26);
        const central = Buffer.alloc(46);
        central.writeUInt32LE(0x02014b50, 0);
        central.writeUInt16LE(20, 4);
        central.writeUInt16LE(20, 6);
        central.writeUInt16LE(0x0800, 8);
        central.writeUInt16LE(fixedModificationTime.dosTime, 12);
        central.writeUInt16LE(fixedModificationTime.dosDate, 14);
        central.writeUInt32LE(checksum, 16);
        central.writeUInt32LE(entry.contents.length, 20);
        central.writeUInt32LE(entry.contents.length, 24);
        central.writeUInt16LE(name.length, 28);
        central.writeUInt32LE(offset, 42);
        localParts.push(local, name, entry.contents);
        centralParts.push(central, name);
        offset += local.length + name.length + entry.contents.length;
    }
    const centralDirectory = Buffer.concat(centralParts);
    const end = Buffer.alloc(22);
    end.writeUInt32LE(0x06054b50, 0);
    end.writeUInt16LE(entries.length, 8);
    end.writeUInt16LE(entries.length, 10);
    end.writeUInt32LE(centralDirectory.length, 12);
    end.writeUInt32LE(offset, 16);
    return Buffer.concat([...localParts, centralDirectory, end]);
}

/// The export as Notion hands it out: a zip of `partCount` part zips, pages spread over them in order.
function notionExportArchive(workspace, partCount) {
    const files = exportFiles(workspace);
    const parts = Array.from({ length: partCount || 1 }, () => []);
    files.forEach((file, fileNumber) => {
        parts[Math.floor(fileNumber * parts.length / files.length)].push({ path: 'Export-' + exportIdentifier + '/' + file.path, contents: file.contents });
    });
    return zipArchive(parts.map((partFiles, partNumber) => ({
        path: 'Export-' + exportIdentifier + '-Part-' + (partNumber + 1) + '.zip',
        contents: zipArchive(partFiles),
    })));
}

/// One part zip on its own, as a person may pick it after unzipping the export.
function notionExportPart(workspace, partCount, partNumber) {
    const files = exportFiles(workspace);
    const partFiles = files.filter((file, fileNumber) => Math.floor(fileNumber * partCount / files.length) === partNumber - 1);
    return zipArchive(partFiles.map((file) => ({ path: 'Export-' + exportIdentifier + '/' + file.path, contents: file.contents })));
}

/// Notion's Markdown and CSV export of the same workspace, which Importer refuses.
function notionMarkdownExportArchive(workspace) {
    const files = workspace.pages.map((page) => ({ path: page.folder + page.fileStem + '.md', contents: Buffer.from('# ' + page.title + '\n') }));
    return zipArchive([{ path: 'Export-' + exportIdentifier + '-Part-1.zip', contents: zipArchive(files) }]);
}

module.exports = { makeSmallWorkspace, makeLargeWorkspace, notionExportArchive, notionExportPart, notionMarkdownExportArchive, zipArchive };

/// `node support/notion-export-fixture.js small <file>` writes the small export as the tests use it (two parts);
/// `node support/notion-export-fixture.js large <page count> <part count> <file>` writes a large one to measure.
if (require.main === module) {
    const fileSystem = require('node:fs');
    const [kind, ...rest] = process.argv.slice(2);
    if (kind === 'small' && rest.length === 1) {
        fileSystem.writeFileSync(rest[0], notionExportArchive(makeSmallWorkspace(), 2));
    } else if (kind === 'large' && rest.length === 3) {
        fileSystem.writeFileSync(rest[2], notionExportArchive(makeLargeWorkspace(Number(rest[0])), Number(rest[1])));
    } else {
        console.error('Usage: notion-export-fixture.js small <file> | large <page count> <part count> <file>');
        process.exit(1);
    }
}
