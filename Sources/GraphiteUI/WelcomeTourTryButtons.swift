/**
 * File: WelcomeTourTryButtons.swift
 * ---------------------------------
 * Layer: UI
 * Description: The welcome tour's last page ends with a button to try the Graphite Guide vault and one to open the Guide.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 17/11/2026
 */

import SwiftUI

/// The two ways to go on from the tour's last page: try Graphite in the Guide vault (made-up recipes, a course and a
/// trip, downloaded the first time), which closes the tour once the vault opens, or read the Guide, which shows over
/// the tour so Done comes back to it; a vault the Guide opens closes the tour as well.
struct WelcomeTourTryButtons: View {
    let closeTour: () -> Void
    @State private var showsGuide = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) { buttons }
            VStack(alignment: .leading, spacing: 12) { buttons }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(.top, 4)
        .guide(isPresented: $showsGuide, didOpenVault: closeTour)
    }

    @ViewBuilder private var buttons: some View {
        GuideVaultButton(title: "Try the Guide Vault", note: nil, didOpen: closeTour)
        Button("Open the Guide", systemImage: "book") { showsGuide = true }
    }
}
