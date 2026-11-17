/**
 * File: notion-api-fixture.js
 * ---------------------------
 * Layer: Tests
 * Description: A made-up Notion workspace answered as Notion's API answers, for the Notion import tests.
 *
 * Authors: Bahey Shalash
 * Version: 1.0
 * Date: 17/11/2026
 */

// Answers the requests Obsidian's Importer makes to Notion's API (version 2025-09-03) from a small
// made-up workspace: a course page with the usual blocks, and a database of lectures under it. The
// answers have the shapes Notion's API reference gives (https://developers.notion.com/reference),
// with only the keys Importer reads, and invented ids and content. It plugs into the test host's
// `networkResponder`, where Graphite would make the request natively (`requestUrl`).
//
// `failures` makes the requests fail as Notion and the network do: a revoked token (401), Notion's
// rate limit (429 with Retry-After), its server errors (5xx), a page no longer shared (404), or no
// network at all.
'use strict';

const token = 'ntn_made_up_test_token';

const pageIdentifier = '10000000-0000-4000-8000-00000000a001';
const databaseIdentifier = '30000000-0000-4000-8000-00000000d001';
const dataSourceIdentifier = '20000000-0000-4000-8000-00000000d001';
const rowIdentifiers = ['10000000-0000-4000-8000-00000000b001', '10000000-0000-4000-8000-00000000b002'];
const editedTime = '2026-10-01T09:15:00.000Z';
const createdTime = '2026-09-01T08:00:00.000Z';

function richText(content, annotations) {
    return [{
        type: 'text', text: { content, link: null }, plain_text: content, href: null,
        annotations: Object.assign({ bold: false, italic: false, strikethrough: false, underline: false, code: false, color: 'default' }, annotations),
    }];
}

let nextBlockNumber = 1;
function block(type, content, hasChildren) {
    const identifier = '40000000-0000-4000-8000-' + String(nextBlockNumber++).padStart(12, '0');
    return { object: 'block', id: identifier, type, has_children: Boolean(hasChildren), archived: false, in_trash: false,
        created_time: createdTime, last_edited_time: editedTime, [type]: content };
}

function titleProperty(content) {
    return { id: 'title', type: 'title', title: richText(content) };
}

function page(identifier, parent, properties, url) {
    return { object: 'page', id: identifier, created_time: createdTime, last_edited_time: editedTime, archived: false, in_trash: false,
        icon: null, cover: null, parent, properties, url: url || 'https://www.notion.so/' + identifier.replace(/-/g, ''), public_url: null };
}

function makeWorkspace() {
    nextBlockNumber = 1;
    const toggle = block('toggle', { rich_text: richText('Why does it converge?'), color: 'default' }, true);
    const pageBlocks = [
        block('heading_1', { rich_text: richText('Fourier series'), color: 'default', is_toggleable: false }),
        block('paragraph', {
            rich_text: [...richText('A periodic signal is a sum of '), ...richText('sines', { bold: true }), ...richText('.')], color: 'default',
        }),
        block('equation', { expression: 'a_k = \\frac{1}{T} \\int_T x(t) e^{-jk\\omega_0 t} \\, dt' }),
        block('code', { rich_text: richText('coefficients = numpy.fft.fft(samples)'), language: 'python', caption: [] }),
        block('callout', {
            rich_text: richText('Coefficients of a real signal are conjugate symmetric.'), icon: { type: 'emoji', emoji: '💡' }, color: 'gray_background',
        }),
        toggle,
        block('to_do', { rich_text: richText('Read chapter 3'), checked: true, color: 'default' }),
        block('bulleted_list_item', { rich_text: richText('Linear'), color: 'default' }),
        Object.assign(block('child_database', { title: 'Lectures' }), { id: databaseIdentifier }),
    ];
    const toggleChildren = [block('paragraph', { rich_text: richText('Because the signal has finite energy over a period.'), color: 'default' })];
    const rowProperties = (title, date, status, isReviewed) => ({
        Name: titleProperty(title),
        Date: { id: 'date', type: 'date', date: { start: date, end: null, time_zone: null } },
        Status: { id: 'status', type: 'select', select: { id: 'select-' + status, name: status, color: 'blue' } },
        Reviewed: { id: 'reviewed', type: 'checkbox', checkbox: isReviewed },
        Pages: { id: 'pages', type: 'number', number: 12 },
    });
    const rowParent = { type: 'data_source_id', data_source_id: dataSourceIdentifier, database_id: databaseIdentifier };
    const rows = [
        page(rowIdentifiers[0], rowParent, rowProperties('Lecture 1: Signals', '2026-09-09', 'Done', true)),
        page(rowIdentifiers[1], rowParent, rowProperties('Lecture 2: Systems', '2026-09-16', 'To review', false)),
    ];
    const coursePage = page(pageIdentifier, { type: 'workspace', workspace: true }, { title: titleProperty('Signals and Systems') });
    const dataSource = {
        object: 'data_source', id: dataSourceIdentifier, created_time: createdTime, last_edited_time: editedTime,
        title: richText('Lectures'), description: [], parent: { type: 'database_id', database_id: databaseIdentifier },
        database_parent: { type: 'page_id', page_id: pageIdentifier }, archived: false, in_trash: false, icon: null, cover: null,
        properties: {
            Name: { id: 'title', name: 'Name', type: 'title', title: {} },
            Date: { id: 'date', name: 'Date', type: 'date', date: {} },
            Status: { id: 'status', name: 'Status', type: 'select', select: { options: [{ id: 'select-Done', name: 'Done', color: 'green' },
                { id: 'select-To review', name: 'To review', color: 'blue' }] } },
            Reviewed: { id: 'reviewed', name: 'Reviewed', type: 'checkbox', checkbox: {} },
            Pages: { id: 'pages', name: 'Pages', type: 'number', number: { format: 'number' } },
        },
    };
    const database = {
        object: 'database', id: databaseIdentifier, created_time: createdTime, last_edited_time: editedTime, title: richText('Lectures'),
        description: [], parent: { type: 'page_id', page_id: pageIdentifier }, is_inline: true, archived: false, in_trash: false,
        icon: null, cover: null, data_sources: [{ id: dataSourceIdentifier, name: 'Lectures' }],
    };
    const blockChildren = new Map([[pageIdentifier, pageBlocks], [toggle.id, toggleChildren], [rowIdentifiers[0], []], [rowIdentifiers[1], []]]);
    return { coursePage, rows, dataSource, database, blockChildren };
}

function list(results) {
    const type = results.length && results[0].object === 'block' ? 'block' : 'page_or_data_source';
    return { object: 'list', results, next_cursor: null, has_more: false, type };
}

function answer(status, body, headers) {
    return {
        status,
        headers: Object.assign({ 'content-type': 'application/json' }, headers),
        bodyBase64: Buffer.from(JSON.stringify(body)).toString('base64'),
    };
}

function notionError(status, code, message) {
    return answer(status, { object: 'error', status, code, message });
}

/// A responder for the test host: `failures` is `{ revokedToken, rateLimitedRequests, serverErrorRequests, failingFromRequest,
/// unsharedAfterRequests, offlineRequests, isOffline }`: the counts say how many requests fail that way, from the `failingFromRequest`th on
/// (the first by default). `requests` collects what was asked.
function makeNotionResponder(failures) {
    const settings = Object.assign({ revokedToken: false, rateLimitedRequests: 0, serverErrorRequests: 0, failingFromRequest: 1,
        unsharedAfterRequests: Infinity, offlineRequests: 0, isOffline: false }, failures);
    const workspace = makeWorkspace();
    const requests = [];
    const responder = (message) => {
        const address = new URL(message.url);
        requests.push(message.method + ' ' + address.pathname);
        const isLosingNetwork = requests.length >= settings.failingFromRequest && settings.offlineRequests > 0;
        if (isLosingNetwork) settings.offlineRequests -= 1;
        if (settings.isOffline || isLosingNetwork) throw Object.assign(new Error('The Internet connection appears to be offline.'), { kind: 'offline' });
        if (address.hostname !== 'api.notion.com') return answer(404, {});
        const authorization = (message.headers || {}).authorization || (message.headers || {}).Authorization;
        if (settings.revokedToken || authorization !== 'Bearer ' + token) return notionError(401, 'unauthorized', 'API token is invalid.');
        const isFailing = requests.length >= settings.failingFromRequest;
        if (isFailing && settings.rateLimitedRequests > 0) {
            settings.rateLimitedRequests -= 1;
            return answer(429, { object: 'error', status: 429, code: 'rate_limited', message: 'Rate limited.' }, { 'retry-after': '1' });
        }
        if (isFailing && settings.serverErrorRequests > 0) {
            settings.serverErrorRequests -= 1;
            return notionError(502, 'internal_server_error', 'Bad gateway.');
        }
        const path = address.pathname;
        const isUnshared = requests.length > settings.unsharedAfterRequests;
        if (path === '/v1/search') return answer(200, list([workspace.coursePage, workspace.dataSource]));
        let match;
        if ((match = /^\/v1\/pages\/([^/]+)$/.exec(path))) {
            const pages = [workspace.coursePage, ...workspace.rows];
            const found = pages.find((candidate) => candidate.id.replace(/-/g, '') === match[1].replace(/-/g, ''));
            if (!found || (isUnshared && found.id !== pageIdentifier)) {
                return notionError(404, 'object_not_found', 'Could not find page with ID: ' + match[1] + '.');
            }
            return answer(200, found);
        }
        if ((match = /^\/v1\/blocks\/([^/]+)\/children$/.exec(path))) {
            const key = Array.from(workspace.blockChildren.keys()).find((candidate) => candidate.replace(/-/g, '') === match[1].replace(/-/g, ''));
            if (!key || (isUnshared && key !== pageIdentifier)) return notionError(404, 'object_not_found', 'Could not find block with ID: ' + match[1] + '.');
            return answer(200, list(workspace.blockChildren.get(key)));
        }
        if ((match = /^\/v1\/databases\/([^/]+)$/.exec(path))) return answer(200, workspace.database);
        if ((match = /^\/v1\/data_sources\/([^/]+)$/.exec(path))) return answer(200, workspace.dataSource);
        if ((match = /^\/v1\/data_sources\/([^/]+)\/query$/.exec(path))) return answer(200, list(workspace.rows));
        if (/^\/v1\/data_sources\/[^/]+\/templates$/.test(path)) return answer(200, { object: 'list', templates: [], has_more: false, next_cursor: null });
        if (path === '/v1/views') return answer(200, { object: 'list', results: [], has_more: false, next_cursor: null });
        if (path === '/v1/users/me') return answer(200, { object: 'user', id: 'bot', type: 'bot', name: 'Test integration', bot: {} });
        return notionError(400, 'invalid_request_url', 'Invalid request URL: ' + path);
    };
    return { responder, requests, token };
}

module.exports = { makeNotionResponder, notionTestToken: token };
