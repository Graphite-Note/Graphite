/**
 * File: CommunityPluginRedrawnSectionTests.swift
 * ----------------------------------------------
 * Layer: Tests
 * Description: A block drawn again while its earlier drawing is under way keeps the newer drawing when the
 *              earlier one's late answer arrives.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */
import XCTest
import GraphiteCore
@testable import GraphiteUI
import GraphiteTestSupport

/// A note's section or code block is drawn again under the same identifier when its width changes
/// (the reading view's `.task` is keyed by the request and the width's step): a scroll bar appearing on
/// the Mac does it. The plugins' page then drops the earlier drawing, which answers that the block
/// "was closed while it was drawn". Seen 2026-11-26 in the Mac app with Meta Bind (issue #235): that
/// late answer arrived after the newer drawing's, was taken for the block's state, and the line of
/// Meta Bind's fields was shown as Graphite's own text, its fields as code.
@MainActor
final class CommunityPluginRedrawnSectionTests: XCTestCase {
    private let testBed = CommunityPluginHostTestBed()

    override func tearDown() async throws {
        await testBed.tearDown()
    }

    /// Its post-processor turns `field` code into a button. Its first drawing waits until the test lets
    /// it go (`releaseFirstDrawing`), as a drawing that waits on a slow read of its note does.
    private static let pluginSource = """
    'use strict';
    const { Plugin } = require('obsidian');
    module.exports = class SlowFieldPlugin extends Plugin {
        onload() {
            let drawings = 0;
            this.registerMarkdownPostProcessor(async (element) => {
                const code = element.querySelector('code');
                if (!code || code.textContent !== 'field') return;
                drawings += 1;
                if (drawings === 1) {
                    window.firstDrawingStarted = true;
                    await new Promise((resolve) => { window.releaseFirstDrawing = resolve; });
                }
                code.replaceWith(createEl('button', { cls: 'field-button', text: 'Field' }));
            });
        }
    };
    """

    func testALateAnswerOfAnEarlierDrawingLeavesTheNewerDrawingShown() async throws {
        let note = "Status `field` today.\n"
        let workspace = try await testBed.workspaceWithRunningPlugins([("slow-field-plugin", Self.pluginSource)], files: ["Note.md": note])
        let host = workspace.communityPlugins
        try await waitUntil("the plugin's post-processor is known") { host.postProcessingPluginIdentifiers.contains("slow-field-plugin") }
        let block = CommunityPluginShownCodeBlock(host: host)
        let request = CommunityPluginReadingBlockRequest(kind: .section, source: note.trimmingCharacters(in: .newlines), note: try VaultPath("Note.md"),
                                                         firstLine: 0, lineCount: 1)

        // The first drawing, at one width, waits in the plugin.
        let firstDrawing = Task { await block.draw(request, width: 400) }
        try await waitUntil("the first drawing reaches the plugin") {
            (try? await self.testBed.evaluate("return window.firstDrawingStarted === true;", in: host)) as? Bool == true
        }
        // The width changes: the same block is drawn again, and that drawing ends first.
        await block.draw(request, width: 600)
        guard case .drawn(let html) = block.appearance else { return XCTFail("The newer drawing is shown: \(block.appearance)") }
        XCTAssertTrue(html.contains("field-button"), html)

        // The earlier drawing's answer arrives late: the plugins' page dropped it for the newer one.
        _ = try await testBed.evaluate("window.releaseFirstDrawing(); return true;", in: host)
        await firstDrawing.value
        guard case .drawn(let shownHTML) = block.appearance else {
            return XCTFail("The earlier drawing's late answer replaced the newer one: \(block.appearance)")
        }
        XCTAssertTrue(shownHTML.contains("field-button"), shownHTML)
        block.release()
    }
}
