/**
 * File: ExternalChangeBanner.swift
 * --------------------------------
 * Layer: UI
 * Description: The banner a note, a PDF or a canvas shows when its file changed in another app: the sentence and the
 *              two choices, side by side where they fit and stacked where they do not.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import SwiftUI

/// "This note changed in another app", with Save a Copy and Use Other Version. On a phone the two buttons took about
/// 215 of 390 points and left the sentence a column of 80 (HUNT-290), so where they do not fit beside it the buttons
/// go under the sentence.
struct ExternalChangeBanner: View {
    let message: String
    let saveCopy: () -> Void
    let useOtherVersion: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                warningSymbol
                Text(message).font(.callout).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                choices
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    warningSymbol
                    Text(message).font(.callout)
                }
                HStack(spacing: 16) { choices }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.12))
    }

    private var warningSymbol: some View {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
    }

    @ViewBuilder private var choices: some View {
        Button("Save a Copy", action: saveCopy)
        Button("Use Other Version", action: useOtherVersion)
    }
}
