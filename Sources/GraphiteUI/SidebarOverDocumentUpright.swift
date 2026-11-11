/**
 * File: SidebarOverDocumentUpright.swift
 * --------------------------------------
 * Layer: UI
 * Description: How an iPad window's split view shows its sidebar: over the documents while the window is taller than
 *              wide, as Notes and Files show theirs, and beside them while it is wider than tall; and how a phone's
 *              file list is brought back to the front when asked for.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 05/11/2026
 */

#if os(iOS)
import SwiftUI
import UIKit

/// Shows the window's sidebar over the documents while the window is taller than wide, and leaves the split view's own
/// choice, beside them, while it is wider than tall. Upright the documents keep the window's whole width whether the
/// sidebar is shown or not: on the owner's 11-inch iPad (2026-11-05) the sidebar stood beside an upright PDF, which was
/// left 514 of the window's 834 points, and the Pencil bar folded its colors into a scrolling strip (HUNT-317).
///
/// SwiftUI has no style that is one thing upright and another sideways, and switching between two styles would build
/// the split view, and every document in it, again at each turn of the iPad. This sets the split behavior of the
/// `UISplitViewController` SwiftUI shows the columns in, which keeps them.
struct SidebarOverDocumentUpright: UIViewControllerRepresentable {
    let isWindowTallerThanWide: Bool

    func makeUIViewController(context: Context) -> SplitBehaviorController {
        let controller = SplitBehaviorController()
        controller.showsSidebarOverDocuments = isWindowTallerThanWide
        return controller
    }

    func updateUIViewController(_ controller: SplitBehaviorController, context: Context) {
        controller.showsSidebarOverDocuments = isWindowTallerThanWide
    }

    /// An empty controller inside the documents' column, which sets the behavior of the split view around it whenever
    /// the window's shape changes or the column is laid out, so an update of the split view that set it back is undone
    /// before the frame is drawn.
    final class SplitBehaviorController: UIViewController {
        var showsSidebarOverDocuments = false {
            didSet { if showsSidebarOverDocuments != oldValue { applySplitBehavior() } }
        }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            applySplitBehavior()
        }

        override func viewWillLayoutSubviews() {
            super.viewWillLayoutSubviews()
            applySplitBehavior()
        }

        /// The behavior the split view had before it was set to show the sidebar over the documents: SwiftUI's own,
        /// which sideways puts the sidebar beside them.
        private var behaviorBesideDocuments: UISplitViewController.SplitBehavior?

        /// Over the documents upright; sideways the behavior SwiftUI gave the split view. A phone's split view is one
        /// stack and has no behavior to set.
        private func applySplitBehavior() {
            guard let splitViewController, !splitViewController.isCollapsed else { return }
            let current = splitViewController.preferredSplitBehavior
            if showsSidebarOverDocuments {
                guard current != .overlay else { return }
                behaviorBesideDocuments = current
                splitViewController.preferredSplitBehavior = .overlay
            } else if let behaviorBesideDocuments, current != behaviorBesideDocuments {
                splitViewController.preferredSplitBehavior = behaviorBesideDocuments
            }
        }
    }
}

/// Brings a phone's file list to the front when asked: a search, a tag or "Reveal current file" asked for while a note
/// is in front. On a phone the split view is collapsed into one navigation stack, the note pushed over the file list.
/// Setting the split view's compact column to the sidebar is taken by SwiftUI but moved nothing on iOS 27, and neither did
/// the split view's own `show(.primary)` (HUNT-183: the note stayed in front, its back button the only way to the list),
/// so the stack is taken back to its first screen, as the back button takes it.
struct CompactFileListReveal: UIViewControllerRepresentable {
    let request: Int

    func makeUIViewController(context: Context) -> RevealController {
        let controller = RevealController()
        controller.handledRequest = request
        return controller
    }

    func updateUIViewController(_ controller: RevealController, context: Context) {
        guard request != controller.handledRequest else { return }
        controller.handledRequest = request
        controller.showFileList()
    }

    /// An empty controller inside the documents' column, which reaches the stack around it.
    final class RevealController: UIViewController {
        var handledRequest = 0

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
        }

        /// The navigation stack that a collapsed split view holds, around this controller, goes back to its first
        /// screen, on the next turn of the main queue, after SwiftUI's update that asked for it.
        func showFileList() {
            DispatchQueue.main.async { [weak self] in
                var ancestor = self?.parent
                while let controller = ancestor {
                    if let stack = controller as? UINavigationController, let split = stack.parent as? UISplitViewController, split.isCollapsed {
                        if stack.viewControllers.count > 1 { stack.popToRootViewController(animated: true) }
                        return
                    }
                    ancestor = controller.parent
                }
            }
        }
    }
}
#endif
