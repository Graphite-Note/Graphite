/**
 * File: PencilSizeChoice.swift
 * ----------------------------
 * Layer: UI
 * Description: One of the Pencil bar's three sizes: of the ink in use, or of the pixel eraser.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 16/11/2026
 */

import SwiftUI

/// One of the bar's three sizes: of the ink in use, or of the pixel eraser.
enum PencilSizeChoice: Equatable {
    case ink(choiceIndex: Int)
    case eraser(choiceIndex: Int)

    var choiceIndex: Int {
        switch self {
        case .ink(let choiceIndex), .eraser(let choiceIndex): choiceIndex
        }
    }
}
