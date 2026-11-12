/**
 * File: WebFrameBlock.swift
 * -------------------------
 * Layer: UI
 * Description: A web frame in a note: a box at the tag's size and look holding the live page near the screen, and its
 *              placeholder, loading indicator and failure message elsewhere.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 12/11/2026
 */

import SwiftUI
import GraphiteCore

/// A web frame (`<iframe>`) in the reading view, Live Preview, an embedded note, a preview card or a printed note. It
/// always takes the tag's size, so the note never moves as its page loads or is given up; the box holds the page only
/// where the frame may be live (`WebFramePresentation`) and, in a scrolling reading view, only while it is near the
/// screen (`WebFrameLiveViews`). Until the page has loaded, and when it cannot, the box shows the site's address.
struct WebFrameBlock: View {
    let frame: WebFrameEmbed
    @Environment(\.webFramePresentation) private var presentation
    @Environment(\.webFrameLiveViews) private var liveViews
    @Environment(\.openURL) private var openURL
    /// The frame among the reading view's, for as long as this view lasts.
    @State private var identity = UUID()
    @State private var page = WebFramePageController()
    /// How many screens away the frame was last measured, told again when the view appears again: a lazy stack can
    /// take a frame's view away and back while its distance stays the same, which reports no change.
    @State private var lastDistance: Double?

    /// The tallest a printed frame's box is: the page itself cannot be printed.
    static let printedHeight: CGFloat = 120

    private var height: CGFloat {
        presentation == .printed ? min(CGFloat(frame.shownHeight), Self.printedHeight) : CGFloat(frame.shownHeight)
    }

    private var holdsPage: Bool {
        presentation == .live && (liveViews?.isLive(identity) ?? true)
    }

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
            .overlay(alignment: .topLeading) {
                GeometryReader { geometry in
                    box.frame(width: CGFloat(frame.shownWidth(columnWidth: Double(geometry.size.width))), height: height)
                }
            }
            .onGeometryChange(for: Double?.self) { geometry in
                guard let visible = geometry.bounds(of: .scrollView) else { return nil }
                // The distance in screens is rounded to a tenth, so a scroll reports a change only now and then.
                let distance = WebFrameLiveSelection.distance(frameTop: 0, frameBottom: geometry.size.height,
                                                              visibleTop: visible.minY, visibleBottom: visible.maxY)
                return (distance * 10).rounded() / 10
            } action: { distance in
                lastDistance = distance
                guard presentation == .live else { return }
                liveViews?.report(distance: distance, of: identity)
            }
            .onAppear { if presentation == .live, let lastDistance { liveViews?.report(distance: lastDistance, of: identity) } }
            .onDisappear { liveViews?.forget(identity) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(frame.name)
    }

    private var box: some View {
        let shape = RoundedRectangle(cornerRadius: CGFloat(frame.cornerRadius), style: .continuous)
        return ZStack {
            if holdsPage {
                WebFramePage(address: frame.address, controller: page, openExternally: { address in openURL(address) })
            }
            if !holdsPage || page.loadState != .loaded {
                WebFramePlaceholder(frame: frame, presentation: presentation, loadState: holdsPage ? page.loadState : nil,
                                    openInBrowser: { openURL(frame.address) }, tryAgain: { page.reload() })
            }
        }
        .clipShape(shape)
        .overlay {
            if let border = frame.border {
                shape.strokeBorder(border.color.map(Self.color(of:)) ?? Color.secondary, lineWidth: CGFloat(border.width))
                    .allowsHitTesting(false)
            }
        }
        // Open in Browser and Copy Address, on the box while it shows no page: a live page keeps its own menus, and an
        // empty menu is not shown.
        .contextMenu {
            if !(holdsPage && page.loadState == .loaded) {
                Button { openURL(frame.address) } label: { Label("Open in Browser", systemImage: "safari") }
                Button { Pasteboard.copy(frame.address.absoluteString) } label: { Label("Copy Address", systemImage: "doc.on.doc") }
            }
        }
    }

    static func color(of color: WebFrameEmbed.Color) -> Color {
        Color(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: color.alpha)
    }
}

/// What a frame shows without its page: the site's address on the note's quiet background, with a progress indicator
/// while the page loads, or why it could not load with Open in Browser and Try Again.
private struct WebFramePlaceholder: View {
    let frame: WebFrameEmbed
    let presentation: WebFramePresentation
    /// Nil while the frame holds no page.
    let loadState: WebFrameLoadState?
    let openInBrowser: () -> Void
    let tryAgain: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            switch loadState {
            case .failed(let message):
                Label("This page can't be shown here.", systemImage: "exclamationmark.triangle")
                    .font(.callout.weight(.medium))
                Text(message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                address
                HStack(spacing: 12) {
                    Button("Open in Browser", action: openInBrowser)
                    Button("Try Again", action: tryAgain)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .loading:
                ProgressView().controlSize(.small)
                address
            case .loaded, nil:
                Image(systemName: "globe").font(.title3).foregroundStyle(.secondary).accessibilityHidden(true)
                if let title = frame.title { Text(title).font(.callout.weight(.medium)).lineLimit(2) }
                address
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(0.35))
    }

    /// The page's address: a link where it is printed, so the PDF opens it; the site's name elsewhere.
    @ViewBuilder private var address: some View {
        if presentation == .printed {
            // Whole, so the finished PDF finds the address in the page's text and links it.
            Text(frame.address.absoluteString).font(.footnote).foregroundStyle(Color.accentColor).lineLimit(3)
        } else {
            Text(frame.siteName).font(.footnote).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
    }
}

/// A web frame in Live Preview, over its concealed tag (`LivePreviewBlock.Kind.webFrame`). Taps and clicks inside the
/// page are the page's; one beside it shows the tag, as on the other rendered blocks, and the block's menu offers Open
/// in Browser and Copy Address above Edit Source. The block's view lives only while its lines are near the screen and
/// is never kept off screen (`DetachedWidgetPool.estimatedMegabytes(of:)`), so it holds its page while it is shown.
struct LivePreviewWebFrameView: View {
    let frame: WebFrameEmbed
    let revealSource: () -> Void
    @Environment(\.renderedBlockMenuContext) private var menuContext
    @Environment(\.openURL) private var openURL

    var body: some View {
        WebFrameBlock(frame: frame)
            .environment(\.webFramePresentation, .live)
            .background { Color.clear.contentShape(Rectangle()).onTapGesture(perform: revealSource) }
            .onAppear {
                let address = frame.address
                let openURL = openURL
                menuContext?.itemsAtPoint = { _ in
                    [RenderedBlockMenuItem(title: "Open in Browser", symbolName: "safari", action: { openURL(address) }),
                     RenderedBlockMenuItem(title: "Copy Address", symbolName: "doc.on.doc", action: { Pasteboard.copy(address.absoluteString) })]
                }
            }
    }
}
