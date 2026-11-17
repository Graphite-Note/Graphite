/**
 * File: LassoSelectionKinds.swift
 * -------------------------------
 * Layer: UI
 * Description: What Graphite's lasso takes: handwriting, images and text boxes, each switched on or off in the
 *              Lasso panel and kept on the device.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import Foundation

/// The kinds of things Graphite's lasso takes, switched in the Lasso panel's "Included in
/// Selection" and in the floating palette's menu (Docs/Lasso-todo.md section 2). Shapes and
/// equations are ink strokes and come with handwriting. Kept between launches, for every canvas.
/// At least one kind is always on.
struct LassoSelectionKinds: OptionSet, Hashable {
    let rawValue: Int

    static let handwriting = LassoSelectionKinds(rawValue: 1 << 0)
    static let images = LassoSelectionKinds(rawValue: 1 << 1)
    static let textBoxes = LassoSelectionKinds(rawValue: 1 << 2)
    static let all: LassoSelectionKinds = [.handwriting, .images, .textBoxes]

    static let preferenceKey = "GraphiteLassoSelectionKinds"
    /// What starts the identifier of a text box among the lasso's pictures on a PDF page.
    static let textBoxIdentifierPrefix = "graphite-text-box:"

    /// One switch of the panel.
    enum Kind: CaseIterable, Identifiable {
        case handwriting, images, textBoxes

        var id: Self { self }
        var title: String {
            switch self {
            case .handwriting: "Handwriting"
            case .images: "Images"
            case .textBoxes: "Text Boxes"
            }
        }
        var symbolName: String {
            switch self {
            case .handwriting: "scribble"
            case .images: "photo"
            case .textBoxes: "character.textbox"
            }
        }
        var option: LassoSelectionKinds {
            switch self {
            case .handwriting: .handwriting
            case .images: .images
            case .textBoxes: .textBoxes
            }
        }
    }

    func includes(_ kind: Kind) -> Bool { contains(kind.option) }

    /// Whether a kind's switch can be turned off: not when it is the last one on.
    func canExclude(_ kind: Kind) -> Bool { includes(kind) && !subtracting(kind.option).isEmpty }

    /// The kinds with one switched on or off; switching off the last one on changes nothing.
    func setting(_ kind: Kind, included: Bool) -> LassoSelectionKinds {
        if included { return union(kind.option) }
        return canExclude(kind) ? subtracting(kind.option) : self
    }

    /// Whether the lasso takes the picture with this identifier: a text box when text boxes
    /// are on, any other picture when images are.
    func takesPicture(identifiedAs identifier: String) -> Bool {
        contains(identifier.hasPrefix(Self.textBoxIdentifierPrefix) ? .textBoxes : .images)
    }

    /// The kinds kept in `defaults`, without any this build does not know; every kind when
    /// none, or none known, is kept.
    static func stored(in defaults: UserDefaults) -> LassoSelectionKinds {
        guard defaults.object(forKey: preferenceKey) != nil else { return .all }
        let kinds = LassoSelectionKinds(rawValue: defaults.integer(forKey: preferenceKey)).intersection(.all)
        return kinds.isEmpty ? .all : kinds
    }

    func store(in defaults: UserDefaults) {
        defaults.set(rawValue, forKey: Self.preferenceKey)
    }

    /// The kinds kept on this device.
    static var stored: LassoSelectionKinds {
        get { stored(in: .standard) }
        set { newValue.store(in: .standard) }
    }
}
