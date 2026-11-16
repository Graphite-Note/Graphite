/**
 * File: PDFStackingOrder.swift
 * ----------------------------
 * Layer: Core
 * Description: The stacking order of a PDF page's objects (pictures, text boxes and shapes) and its Pencil ink,
 *              as plain values: where an object goes when it is brought forward or sent back, where new ink
 *              and new pictures go, and which annotations a reorder takes off the page and puts back.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

/// One annotation of a PDF page as the stacking order sees it.
public enum PDFStackingEntry: Hashable, Sendable {
    /// A picture, text box or shape the person can select and arrange; `name` is its
    /// annotation name, nil for another application's unnamed shape.
    case object(PDFStackedObjectKind, name: String?)
    /// A link over a text box's text, which goes wherever its box goes.
    case attached(ownerName: String)
    /// One stroke of Graphite's Pencil ink. All of a page's ink is one layer.
    case ink
    /// Anything else: another application's annotation, a text mark, a link. It is never taken
    /// off the page, so it keeps its place among the page's other fixed annotations.
    case fixed
}

public enum PDFStackedObjectKind: Hashable, Sendable {
    case picture, textBox, shape
}

/// What Arrange does to the selected object, or, for undo, where it puts it back.
public enum PDFArrangement: Hashable, Sendable {
    case bringToFront, bringForward, sendBackward, sendToBack
    /// At this place among the page's layers (`PDFStackingOrder.layers`), the lowest being 0.
    case position(Int)
}

/// The page's annotations a change of order takes off and adds back, in the order they are
/// added back. PDFKit only appends annotations, so the order is changed by taking off a
/// page's last layers and adding them again; fixed annotations are never taken off.
public struct PDFStackingChange: Equatable, Sendable {
    /// Indices into the page's annotations, in the order they are added back.
    public let annotationIndicesAddedBack: [Int]
}

/// The order of a page's layers: each object (a text box with its links) and the ink as one
/// layer, the lowest first, at the place of the annotation that draws it last (for the ink,
/// its last stroke).
///
/// Arranging steps over objects only: Bring Forward passes the next object up, Bring to
/// Front puts the object right over the topmost other one. An object goes over or under the
/// ink only to pass an object on the other side of it, so pictures written on stay under
/// their writing when they are arranged among themselves (invariant M-15).
public struct PDFStackingOrder: Equatable, Sendable {
    public enum Layer: Hashable, Sendable {
        /// An object, by the index of its annotation in the page's annotations.
        case object(annotationIndex: Int)
        case ink
    }

    public let entries: [PDFStackingEntry]
    /// The page's layers, the lowest first.
    public let layers: [Layer]
    /// The annotations each layer draws, in the page's order: an object first, then its links.
    private let annotationIndicesByLayer: [Layer: [Int]]

    public init(entries: [PDFStackingEntry]) {
        self.entries = entries
        var linkIndicesByOwner: [String: [Int]] = [:]
        var objectIndicesByName: [String: Int] = [:]
        for (index, entry) in entries.enumerated() {
            switch entry {
            case .attached(let ownerName): linkIndicesByOwner[ownerName, default: []].append(index)
            case .object(_, let name?): if objectIndicesByName[name] == nil { objectIndicesByName[name] = index }
            case .object(_, nil), .ink, .fixed: break
            }
        }
        var anchoredLayers: [(anchor: Int, layer: Layer)] = []
        var indicesByLayer: [Layer: [Int]] = [:]
        var inkIndices: [Int] = []
        for (index, entry) in entries.enumerated() {
            switch entry {
            case .object(_, let name):
                let layer = Layer.object(annotationIndex: index)
                // Links belong to the first object of their owner's name.
                let links = name.flatMap { ownerName in objectIndicesByName[ownerName] == index ? linkIndicesByOwner[ownerName] : nil } ?? []
                indicesByLayer[layer] = [index] + links
                anchoredLayers.append((index, layer))
            case .ink:
                inkIndices.append(index)
            case .attached, .fixed:
                break
            }
        }
        if let lastStroke = inkIndices.last {
            indicesByLayer[.ink] = inkIndices
            anchoredLayers.append((lastStroke, .ink))
        }
        layers = anchoredLayers.sorted { leftLayer, rightLayer in leftLayer.anchor < rightLayer.anchor }.map(\.layer)
        annotationIndicesByLayer = indicesByLayer
    }

    /// The annotations a layer draws, in the page's order.
    public func annotationIndices(of layer: Layer) -> [Int] {
        annotationIndicesByLayer[layer] ?? []
    }

    /// The object layer of the annotation at this index, or nil when it is not an object.
    public func layer(ofObjectAt annotationIndex: Int) -> Layer? {
        let layer = Layer.object(annotationIndex: annotationIndex)
        return annotationIndicesByLayer[layer] == nil ? nil : layer
    }

    public func position(of layer: Layer) -> Int? {
        layers.firstIndex(of: layer)
    }

    /// Whether the page has Graphite ink.
    public var hasInk: Bool { annotationIndicesByLayer[.ink] != nil }

    /// Where the ink is among the layers, or, on a page without ink, where its first stroke
    /// goes: under the page's top run of text boxes, which are over the ink as they always were.
    public var inkPosition: Int {
        if let inkPosition = position(of: .ink) { return inkPosition }
        var position = layers.count
        while position > 0, case .object(let annotationIndex) = layers[position - 1], case .object(.textBox, _) = entries[annotationIndex] {
            position -= 1
        }
        return position
    }

    /// The layers over the ink (or over where it goes), the lowest first: drawn over the ink on
    /// screen, and put back after new strokes.
    public var layersOverInk: ArraySlice<Layer> {
        let inkPosition = inkPosition
        return layers[(hasInk ? inkPosition + 1 : inkPosition)...]
    }

    /// The layers in their order once `layer` is arranged, or nil when it stays where it is.
    public func arranged(_ layer: Layer, _ arrangement: PDFArrangement) -> [Layer]? {
        guard let formerPosition = position(of: layer) else { return nil }
        var arrangedLayers = layers
        arrangedLayers.remove(at: formerPosition)
        guard let newPosition = newPosition(of: layer, arrangement, amongTheOthers: arrangedLayers) else { return nil }
        arrangedLayers.insert(layer, at: newPosition)
        return arrangedLayers == layers ? nil : arrangedLayers
    }

    /// Where `layer` goes among `otherLayers`, the page's layers without it.
    private func newPosition(of layer: Layer, _ arrangement: PDFArrangement, amongTheOthers otherLayers: [Layer]) -> Int? {
        if case .position(let requestedPosition) = arrangement { return min(max(requestedPosition, 0), otherLayers.count) }
        if layer == .ink {
            // The ink as a layer of its own: over or under every object.
            switch arrangement {
            case .bringToFront: return otherLayers.count
            case .sendToBack: return 0
            case .bringForward, .sendBackward, .position: return nil
            }
        }
        let objectLayers = layers.filter { candidate in candidate != .ink }
        guard let objectPosition = objectLayers.firstIndex(of: layer) else { return nil }
        let passedObjectPosition = switch arrangement {
        case .bringToFront: objectLayers.count - 1
        case .bringForward: objectPosition + 1
        case .sendBackward: objectPosition - 1
        case .sendToBack, .position: 0
        }
        guard passedObjectPosition != objectPosition, objectLayers.indices.contains(passedObjectPosition),
              let passedPosition = otherLayers.firstIndex(of: objectLayers[passedObjectPosition]) else { return nil }
        // Right over the object passed going up, right under it going down.
        return passedObjectPosition > objectPosition ? passedPosition + 1 : passedPosition
    }

    /// The annotations to take off and add back so the layers are in `newOrder`, which holds the
    /// same layers. The longest start of `newOrder` already in that order stays on the page.
    public func change(to newOrder: [Layer]) -> PDFStackingChange {
        precondition(newOrder.count == layers.count && Set(newOrder) == Set(layers), "A new order holds the same layers.")
        var keptCount = 0
        var searchStart = 0
        for layer in newOrder {
            guard let found = layers[searchStart...].firstIndex(of: layer) else { break }
            keptCount += 1
            searchStart = found + 1
        }
        return PDFStackingChange(annotationIndicesAddedBack: newOrder[keptCount...].flatMap { layer in annotationIndices(of: layer) })
    }

    /// The annotations to take off before new strokes are added, and to add back after them,
    /// so the strokes join the ink layer: those of the layers over the ink.
    public var annotationIndicesOverInk: [Int] {
        layersOverInk.flatMap { layer in annotationIndices(of: layer) }
    }

    /// The layers once an object just added on top goes to `position`: where a new picture
    /// goes, right under the ink (`inkPosition` before it was added).
    public func placingTopLayer(at position: Int) -> [Layer]? {
        guard let topLayer = layers.last else { return nil }
        return arranged(topLayer, .position(position))
    }
}
