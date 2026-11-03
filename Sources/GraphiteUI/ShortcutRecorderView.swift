/**
 * File: ShortcutRecorderView.swift
 * --------------------------------
 * Layer: UI
 * Description: Takes the keyboard while a keyboard shortcut is recorded and reports the first key combination pressed, or that the recording ended without one.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 01/11/2026
 */

import SwiftUI
import GraphiteCore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// What a recording ended with.
enum ShortcutRecording {
    case recorded(KeyCombination)
    /// Escape was pressed alone.
    case cancelled
}

/// Takes the keyboard while a shortcut is recorded: the next key pressed with its modifiers is
/// the shortcut, and Escape alone cancels. A modifier key pressed alone is waited past.
struct ShortcutRecorderView: View {
    let finish: (ShortcutRecording) -> Void

    var body: some View {
        KeyPressCatcher(finish: finish)
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
    }

    static func recording(of combination: KeyCombination) -> ShortcutRecording {
        combination == KeyCombination([], .named(.escape)) ? .cancelled : .recorded(combination)
    }
}

#if canImport(UIKit)
private struct KeyPressCatcher: UIViewRepresentable {
    let finish: (ShortcutRecording) -> Void

    func makeUIView(context: Context) -> KeyPressCatcherView {
        KeyPressCatcherView(finish: finish)
    }

    func updateUIView(_ view: KeyPressCatcherView, context: Context) {}
}

/// A view that becomes first responder and reports the first key press. The menu bar gives up
/// its shortcuts while it records (`VaultKeyboardShortcuts.recordingCommandIdentifier`), so ⌘
/// shortcuts reach it too.
final class KeyPressCatcherView: UIView {
    private let finish: (ShortcutRecording) -> Void
    private var hasFinished = false

    init(finish: @escaping (ShortcutRecording) -> Void) {
        self.finish = finish
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { becomeFirstResponder() }
    }

    /// The keyboard went elsewhere, so no key will come here: the recording ends. Left
    /// running, the menu bar would keep giving up its shortcuts (`VaultKeyboardShortcuts`).
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { endWithoutShortcut() }
        return resigned
    }

    private func endWithoutShortcut() {
        guard !hasFinished else { return }
        hasFinished = true
        finish(.cancelled)
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard !hasFinished, let combination = presses.lazy.compactMap({ press in press.key.flatMap(KeyCombination.init(key:)) }).first else {
            super.pressesBegan(presses, with: event)
            return
        }
        hasFinished = true
        finish(ShortcutRecorderView.recording(of: combination))
    }
}
#else
private struct KeyPressCatcher: NSViewRepresentable {
    let finish: (ShortcutRecording) -> Void

    func makeNSView(context: Context) -> KeyPressCatcherView {
        KeyPressCatcherView(finish: finish)
    }

    func updateNSView(_ view: KeyPressCatcherView, context: Context) {}
}

/// A view that becomes first responder and reports the first key press, ⌘ shortcuts included:
/// a window asks its views for key equivalents before the menu bar.
final class KeyPressCatcherView: NSView {
    private let finish: (ShortcutRecording) -> Void
    private var hasFinished = false

    init(finish: @escaping (ShortcutRecording) -> Void) {
        self.finish = finish
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        guard let window else { return }
        window.makeFirstResponder(self)
        // The window can lose the keyboard while this view stays its first responder, so
        // keys typed in another window or app never arrive here: the recording ends.
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidResignKey), name: NSWindow.didResignKeyNotification, object: window)
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { endWithoutShortcut() }
        return resigned
    }

    @objc private func windowDidResignKey(_ notification: Notification) {
        endWithoutShortcut()
    }

    private func endWithoutShortcut() {
        guard !hasFinished else { return }
        hasFinished = true
        finish(.cancelled)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        return record(event)
    }

    override func keyDown(with event: NSEvent) {
        if !record(event) { super.keyDown(with: event) }
    }

    private func record(_ event: NSEvent) -> Bool {
        guard !hasFinished, let combination = KeyCombination(event: event) else { return false }
        hasFinished = true
        finish(ShortcutRecorderView.recording(of: combination))
        return true
    }
}
#endif
