/**
 * File: PDFPasswordPromptTests.swift
 * ----------------------------------
 * Layer: Tests
 * Description: The protected PDF's password prompt laid out in a Mac window as wide as the owner's: the field at a Mac
 *              password prompt's width, the Unlock button with its whole title, and no Passwords suggestions asked for.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 11/11/2026
 */

#if os(macOS)
import AppKit
import SwiftUI
import Vision
import XCTest
@testable import GraphiteUI
import GraphiteTestSupport

/// HUNT-327: in a 1,370-point window the field read "Pass" and the button "U…", and the Passwords
/// pop-up opened over them as the prompt appeared.
@MainActor
final class PDFPasswordPromptTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() async throws {
        for window in windows { window.close() }
        windows = []
    }

    private func showPrompt(width: CGFloat) -> NSHostingView<some View> {
        let size = CGSize(width: width, height: 800)
        let prompt = PDFPasswordPrompt(fileName: "Locked lecture.pdf", message: "This PDF is protected by a password.") { _ in }
        let hosting = NSHostingView(rootView: prompt.frame(width: size.width, height: size.height))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.showInvisibly()
        windows.append(window)
        hosting.layoutSubtreeIfNeeded()
        return hosting
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { child in [child] + descendants(of: child) }
    }

    private func passwordField(in hosting: NSView) -> NSSecureTextField? {
        descendants(of: hosting).compactMap { view in view as? NSSecureTextField }.first
    }

    /// The texts the view draws, read from its pixels by the system's text recognition: SwiftUI draws the prominent
    /// Unlock button itself, with no AppKit button or accessibility element to measure in a window no one sees.
    private func drawnTexts(in view: NSView) throws -> [String] {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: try XCTUnwrap(bitmap.cgImage)).perform([request])
        return (request.results ?? []).compactMap { observation in observation.topCandidates(1).first?.string }
    }

    func testTheFieldIsAsWideAsAMacPasswordPromptsAndAsksForNoPasswordsSuggestions() async throws {
        for windowWidth in [1_370, 600] as [CGFloat] {
            let hosting = showPrompt(width: windowWidth)
            var foundField: NSSecureTextField?
            try await waitUntil("the prompt's field in a \(Int(windowWidth))-point window") {
                foundField = self.passwordField(in: hosting)
                return foundField != nil
            }
            let field = try XCTUnwrap(foundField)
            XCTAssertEqual(field.frame.width, PDFPasswordPrompt.passwordFieldWidth, accuracy: 1,
                           "In a \(Int(windowWidth))-point window the field is a Mac password prompt's width, not squeezed.")
            XCTAssertNil(field.contentType, "A PDF's password is the file's, so the Passwords app's suggestions are not asked for.")
        }
    }

    func testTheFieldsPlaceholderAndTheUnlockButtonAreDrawnWhole() async throws {
        // The drawn text is read with Vision, which GitHub's virtual Macs cannot run.
        try await TextRecognitionCapability.requireOnDeviceTextRecognition()
        let hosting = showPrompt(width: 1_370)
        var texts: [String] = []
        try await waitUntil("the prompt's title is drawn") {
            texts = try self.drawnTexts(in: hosting)
            return texts.contains { text in text.contains("Is Locked") }
        }
        XCTAssertTrue(texts.contains("Password"), "The placeholder reads whole, not \"Pass\": \(texts)")
        XCTAssertTrue(texts.contains("Unlock"), "The button reads whole, not \"U…\": \(texts)")
    }
}
#endif
