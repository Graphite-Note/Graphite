/**
 * File: LassoOptionsPanel.swift
 * -----------------------------
 * Layer: UI
 * Description: The Lasso panel the Pencil bar opens with a second tap on the lasso in use: the lasso's type and
 *              the kinds it takes.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import SwiftUI

#if canImport(UIKit)
/// The Lasso panel (Docs/Lasso-todo.md section 2): Rectangle and Freehand as two large
/// choices, and the "Included in Selection" switches (`LassoSelectionKinds`). Text Boxes is
/// shown only where text boxes go, on PDF pages. Both are kept for every canvas.
struct LassoOptionsPanel: View {
    var offersTextBoxes = false
    @AppStorage(LassoShape.preferenceKey) private var lassoShape = LassoShape.freehand
    @AppStorage(LassoSelectionKinds.preferenceKey) private var storedKinds = LassoSelectionKinds.all.rawValue

    /// The switches shown: Text Boxes only where there are text boxes.
    static func shownKinds(offersTextBoxes: Bool) -> [LassoSelectionKinds.Kind] {
        LassoSelectionKinds.Kind.allCases.filter { kind in kind != .textBoxes || offersTextBoxes }
    }

    private var kinds: LassoSelectionKinds {
        let kinds = LassoSelectionKinds(rawValue: storedKinds).intersection(.all)
        return kinds.isEmpty ? .all : kinds
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Lasso Type").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach([LassoShape.rectangle, .freehand]) { shape in shapeButton(shape) }
            }
            Text("Included in Selection").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                let shown = Self.shownKinds(offersTextBoxes: offersTextBoxes)
                ForEach(shown) { kind in
                    kindToggle(kind)
                    if kind != shown.last { Divider() }
                }
            }
            .padding(.horizontal, 12)
            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(16)
        .frame(width: 300)
    }

    private func shapeButton(_ shape: LassoShape) -> some View {
        let isChosen = lassoShape == shape
        return Button {
            lassoShape = shape
        } label: {
            VStack(spacing: 6) {
                Image(systemName: shape.symbolName).font(.title2)
                Text(shape.title).font(.callout)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(isChosen ? AnyShapeStyle(.primary.opacity(0.14)) : AnyShapeStyle(.primary.opacity(0.04)), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(shape.title)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    private func kindToggle(_ kind: LassoSelectionKinds.Kind) -> some View {
        let kinds = kinds
        return Toggle(isOn: Binding(get: { kinds.includes(kind) },
                                    set: { included in storedKinds = kinds.setting(kind, included: included).rawValue })) {
            Label(kind.title, systemImage: kind.symbolName)
        }
        // The last kind on stays on: the lasso always takes something.
        .disabled(kinds.includes(kind) && !kinds.canExclude(kind))
        .padding(.vertical, 8)
    }
}
#endif
