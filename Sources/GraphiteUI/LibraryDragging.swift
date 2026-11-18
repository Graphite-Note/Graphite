/**
 * File: LibraryDragging.swift
 * ---------------------------
 * Layer: UI
 * Description: How the library's tiles drag: every chosen tile in one drag where the system has drag
 *              containers (macOS 26, iOS 27), the touched tile alone on iOS 26.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 18/11/2026
 */

import GraphiteCore
import SwiftUI

extension LibraryEntryPresentation {
    /// What a drag of the item at `rawPath` carries.
    func draggedItem(forRawPath rawPath: String) -> VaultItemTransfer {
        let location = (try? VaultPath(rawPath)).flatMap(fileLocation) // A name no vault path can hold has no file to give.
        return VaultItemTransfer(path: rawPath, fileLocation: location, vaultRoot: fileLocation(.root))
    }
}

/// The grid: a drag that starts on a chosen tile carries every chosen tile.
struct LibraryGridDragContainer: ViewModifier {
    let entries: LibraryEntryPresentation
    let chosenRawPaths: [String]

    func body(content: Content) -> some View {
        if #available(iOS 27, *) {
            content
                .dragContainer(for: VaultItemTransfer.self, itemID: \.path) { draggedPaths in draggedPaths.map(entries.draggedItem(forRawPath:)) }
                .dragContainerSelection(chosenRawPaths)
        } else {
            content
        }
    }
}

/// One tile: an item of the grid's drag container, or on iOS 26 a drag of its own.
struct LibraryTileDraggable: ViewModifier {
    let entries: LibraryEntryPresentation
    let rawPath: String

    func body(content: Content) -> some View {
        if #available(iOS 27, *) {
            content.draggable(containerItemID: rawPath)
        } else {
            content.draggable(entries.draggedItem(forRawPath: rawPath))
        }
    }
}
