/**
 * File: community-plugin-runtime-markdown-conversion.js
 * -----------------------------------------------------
 * Layer: Plugin runtime
 * Description: Obsidian's `htmlToMarkdown`, made with Turndown as Obsidian makes it.
 *
 * Authors: Bahey Shalash
 * Version: 1.0
 * Date: 17/11/2026
 */

// Obsidian's `htmlToMarkdown` is Turndown underneath, and Obsidian gives plugins Turndown
// itself as `window.TurndownService` (Importer's Evernote conversion reads it). The options and
// rules below are those Obsidian's own Importer uses to stand in for Obsidian outside the app
// (`web/obsidian/core.ts` in obsidianmd/obsidian-importer, MIT, Copyright (c) 2023 Obsidian),
// checked there against the app byte for byte on its HTML and Notion exports. Importers write
// every note through this, so a difference here is a difference in every imported note.
(function installMarkdownConversion(globalScope) {
    'use strict';

    const runtime = globalScope.GraphitePluginRuntime;
    const exportedApi = runtime.obsidianModule;

    /// Everything Obsidian's `htmlToMarkdown` accepts, as markup Turndown reads.
    function markupOf(html) {
        if (typeof html === 'string') return html;
        if (html && 'outerHTML' in html) return html.outerHTML;
        if (html && 'documentElement' in html) return html.documentElement.outerHTML;
        // A fragment has no markup of its own, only its children's.
        return Array.from((html && html.childNodes) || []).map((node) => node.outerHTML || node.textContent || '').join('');
    }

    /// Obsidian percent-encodes a space in a link target, where Turndown wraps the target in angle brackets.
    function escapedAddress(address) {
        return address.replace(/ /g, '%20').replace(/([()])/g, '\\$1');
    }

    function titleSuffix(element) {
        const title = element.getAttribute('title');
        return title ? ' "' + title + '"' : '';
    }

    function tableRows(table) {
        const rows = [];
        for (const child of Array.from(table.children)) {
            if (child.tagName === 'TR') rows.push(child);
            else if (child.tagName === 'THEAD' || child.tagName === 'TBODY' || child.tagName === 'TFOOT') {
                rows.push(...Array.from(child.children).filter((row) => row.tagName === 'TR'));
            }
        }
        return rows;
    }

    function tableCells(row) {
        return Array.from(row.children).filter((cell) => cell.tagName === 'TD' || cell.tagName === 'TH');
    }

    /// Obsidian's unpadded, ragged tables, with an empty header row made up when the table has none.
    /// An empty table gives nothing.
    function tableMarkdown(table, service) {
        const rows = tableRows(table).filter((row) => tableCells(row).length > 0);
        if (rows.length === 0) return '';
        const columnCount = Math.max(...rows.map((row) => tableCells(row).length));
        const cellText = (cell) => service.turndown(cell.innerHTML).replace(/\n/g, '<br>').replace(/\|/g, '\\|');
        const rowLine = (row, isPadded) => {
            const cells = tableCells(row).map(cellText);
            while (isPadded && cells.length < columnCount) cells.push('   ');
            return '|' + cells.join('|') + '|';
        };
        const separatorLine = '|' + Array(columnCount).fill('---').join('|') + '|';
        const headerSection = Array.from(table.children).find((child) => child.tagName === 'THEAD');
        const firstChildName = table.firstElementChild ? table.firstElementChild.tagName : '';
        const isFirstRowHeader = (firstChildName === 'TBODY' || firstChildName === 'TR') && tableCells(rows[0]).every((cell) => cell.tagName === 'TH');
        const headerRow = headerSection ? tableRows(headerSection)[0] : (isFirstRowHeader ? rows[0] : null);
        const lines = [];
        if (!headerRow) {
            lines.push('|' + Array(columnCount).fill('   ').join('|') + '|');
            lines.push(separatorLine);
        }
        for (const child of Array.from(table.children)) {
            if (child.tagName === 'CAPTION') {
                lines.push(service.turndown(child.innerHTML));
                continue;
            }
            for (const row of child.tagName === 'TR' ? [child] : tableRows(child)) {
                if (tableCells(row).length === 0) continue;
                lines.push(rowLine(row, row === headerRow));
                if (row === headerRow) lines.push(separatorLine);
            }
        }
        return lines.join('\n');
    }

    function listItemMarkdown(content, item) {
        const body = content.replace(/^\n+/, '').replace(/\n+$/, '\n').replace(/\n/gm, '\n    ');
        let marker = '- ';
        const list = item.parentNode;
        if (list && list.nodeName === 'OL') {
            // A start nobody can read counts from one.
            const start = Number(list.getAttribute('start'));
            const position = Array.prototype.indexOf.call(list.children, item);
            marker = (Number.isFinite(start) && list.getAttribute('start') ? start + position : position + 1) + '. ';
        }
        return marker + body + (item.nextSibling && !/\n$/.test(body) ? '\n' : '');
    }

    function makeConversionService() {
        const service = new globalScope.TurndownService({ headingStyle: 'atx', codeBlockStyle: 'fenced', emDelimiter: '_', bulletListMarker: '-', hr: '---' });
        // Obsidian does not escape Markdown punctuation coming out of HTML: a callout's [!important] stays as written.
        service.escape = (text) => text;
        // Obsidian drops these rather than letting their text through when a whole document is converted.
        service.remove(['head', 'title', 'style', 'script', 'iframe']);
        service.addRule('inlineLink', {
            filter: (node) => node.nodeName === 'A' && node.getAttribute('href'),
            replacement: (content, node) => '[' + content + '](' + escapedAddress(node.getAttribute('href')) + titleSuffix(node) + ')',
        });
        service.addRule('image', {
            filter: 'img',
            replacement: (content, node) => {
                const address = node.getAttribute('src');
                return address ? '![' + (node.getAttribute('alt') || '') + '](' + escapedAddress(address) + titleSuffix(node) + ')' : '';
            },
        });
        service.addRule('highlight', { filter: ['mark'], replacement: (content) => '==' + content + '==' });
        service.addRule('strikethrough', { filter: ['del', 's', 'strike'], replacement: (content) => '~~' + content + '~~' });
        // Turndown pads a list marker to four columns; Obsidian writes one space and indents the item's lines by four.
        service.addRule('listItem', { filter: 'li', replacement: listItemMarkdown });
        service.addRule('table', { filter: 'table', replacement: (content, node) => '\n\n' + tableMarkdown(node, service) + '\n\n' });
        return service;
    }

    /// One service serves every call: its rules hold no state between conversions.
    let conversionService = null;

    function htmlToMarkdown(html) {
        if (!conversionService) conversionService = makeConversionService();
        return conversionService.turndown(markupOf(html));
    }

    exportedApi.htmlToMarkdown = htmlToMarkdown;
}(typeof window !== 'undefined' ? window : globalThis));
