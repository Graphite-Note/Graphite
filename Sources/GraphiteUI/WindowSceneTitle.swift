/**
 * File: WindowSceneTitle.swift
 * ----------------------------
 * Layer: UI
 * Description: Names a window after the document it shows, so the iPad's app switcher tells Graphite's windows apart,
 *              as it does for Files and Preview.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

#if canImport(UIKit)
import SwiftUI
import UIKit

/// Gives the window scene this view is in the document's name: the app switcher shows a scene's `title` under the app's
/// name, and `navigationTitle` does not reach it. An empty title, the library's, shows the app's name alone.
struct WindowSceneTitle: UIViewRepresentable {
    let title: String

    func makeUIView(context: Context) -> WindowSceneTitleView { WindowSceneTitleView() }

    func updateUIView(_ view: WindowSceneTitleView, context: Context) { view.title = title }
}

/// An empty view that writes its title to the scene of the window it is in, when either changes.
final class WindowSceneTitleView: UIView {
    var title = "" {
        didSet { if title != oldValue { nameWindowScene() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        nameWindowScene()
    }

    private func nameWindowScene() {
        guard let windowScene = window?.windowScene, windowScene.title != title else { return }
        windowScene.title = title
    }
}
#endif
