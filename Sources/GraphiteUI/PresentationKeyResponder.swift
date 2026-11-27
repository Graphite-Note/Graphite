/**
 * File: PresentationKeyResponder.swift
 * ------------------------------------
 * Layer: UI
 * Description: A hardware keyboard's keys during a presentation on the iPad and the iPhone, read by a UIKit
 *              responder whose input view is empty: while a menu was open, iOS raised the software keyboard over
 *              the slide for whichever view held the keys (seen on the iPhone with the Pencil menu, first with
 *              SwiftUI's key focus, then with a plain responder).
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 27/11/2026
 */

#if os(iOS)
import SwiftUI
import UIKit

/// Takes the presentation's keys (`PresentationKeys`) while the presentation's screen is shown on the device.
struct PresentationKeyResponder: UIViewRepresentable {
    let perform: (PresentationRequest) -> Void

    func makeUIView(context: Context) -> PresentationKeyResponderView {
        let responder = PresentationKeyResponderView()
        responder.perform = perform
        return responder
    }

    func updateUIView(_ responder: PresentationKeyResponderView, context: Context) {
        responder.perform = perform
    }
}

/// An empty view that is the first responder while shown, so the keys of a hardware keyboard reach it. Its input
/// view is empty, so where iOS would show the software keyboard for it, it shows nothing.
final class PresentationKeyResponderView: UIView {
    var perform: ((PresentationRequest) -> Void)?
    private let emptyInputView = UIView(frame: .zero)

    override var canBecomeFirstResponder: Bool { true }
    override var inputView: UIView? { emptyInputView }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        // On the next turn of the main queue: becoming first responder inside SwiftUI's update loops it.
        Task { @MainActor [weak self] in self?.becomeFirstResponder() }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let requests = presses.compactMap { press in press.key.flatMap(Self.request(for:)) }
        guard !requests.isEmpty else { return super.pressesBegan(presses, with: event) }
        for request in requests { perform?(request) }
    }

    /// The presentation's request for a key, as `PresentationKeys` reads SwiftUI's keys.
    static func request(for key: UIKey) -> PresentationRequest? {
        guard let equivalent = keyEquivalent(for: key) else { return nil }
        return PresentationKeys.request(for: equivalent, modifiers: modifiers(of: key.modifierFlags))
    }

    static func keyEquivalent(for key: UIKey) -> KeyEquivalent? {
        switch key.keyCode {
        case .keyboardRightArrow: .rightArrow
        case .keyboardLeftArrow: .leftArrow
        case .keyboardUpArrow: .upArrow
        case .keyboardDownArrow: .downArrow
        case .keyboardPageUp: .pageUp
        case .keyboardPageDown: .pageDown
        case .keyboardHome: .home
        case .keyboardEnd: .end
        case .keyboardEscape: .escape
        case .keyboardReturnOrEnter, .keypadEnter: .return
        case .keyboardDeleteOrBackspace: .delete
        case .keyboardDeleteForward: .deleteForward
        case .keyboardSpacebar: .space
        default: key.charactersIgnoringModifiers.first.map { character in KeyEquivalent(character) }
        }
    }

    static func modifiers(of flags: UIKeyModifierFlags) -> EventModifiers {
        var modifiers: EventModifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.alternate) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return modifiers
    }
}
#endif
