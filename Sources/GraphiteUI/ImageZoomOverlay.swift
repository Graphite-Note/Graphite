/**
 * File: ImageZoomOverlay.swift
 * ----------------------------
 * Layer: UI
 * Description: Shows a picture of a note zoomed in over the window, as Obsidian's image zoom does.
 *
 * Authors: Bahey Shalash
 * Version: 0.8
 * Date: 09/11/2026
 */

import SwiftUI
import GraphiteCore
import GraphiteApple

/// A picture shown over the whole window on a dark backdrop, fitted to the window, with its
/// file name at the top and a close button, as Obsidian zooms into an image. It replaces a
/// separate full-screen viewer or Quick Look window: the note stays where it was behind it.
/// Pinch, double-tap (double-click on the Mac) and the trackpad zoom further; Escape, the
/// close button or a tap on the picture while it is fitted closes it.
struct ImageZoomOverlay: View {
    let location: URL
    let title: String
    /// Opens the drawing editor over the picture; nil where the picture cannot be drawn on.
    var drawOnImage: (() -> Void)? = nil
    let close: () -> Void
    @State private var image: CGImage?
    @State private var message: String?
    /// The zoom takes the keyboard from the note behind it, so Escape closes it and typing
    /// does not reach the note.
    @FocusState private var hasKeyboardFocus: Bool

    /// The largest side decoded, so a huge photo is sharp when zoomed without holding its
    /// full size in memory.
    static let maximumPixelDimension = 4096

    var body: some View {
        ZStack {
            Color.black.opacity(0.92)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .accessibilityHidden(true)
            if let image {
                ZoomedPicture(image: image, closeWhenTappedFitted: close)
                    .ignoresSafeArea()
                    .accessibilityLabel(title)
                    .accessibilityAddTraits(.isImage)
            } else if let message {
                ContentUnavailableView("Can't Show This Image", systemImage: "photo", description: Text(message))
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .overlay(alignment: .top) { titleBar }
        .environment(\.colorScheme, .dark)
        .accessibilityAddTraits(.isModal)
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeyboardFocus)
        .onKeyPress(.escape) {
            close()
            return .handled
        }
        .onAppear { hasKeyboardFocus = true }
        .task(id: location) {
            do {
                image = try await ImageFileService().displayImage(at: location, maximumPixelDimension: Self.maximumPixelDimension)
            } catch {
                if !Task.isCancelled { message = error.localizedDescription }
            }
        }
    }

    /// The file name in the middle, the actions at the right.
    private var titleBar: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            if let drawOnImage {
                Button("Draw on Image", systemImage: "pencil.tip.crop.circle.badge.plus", action: drawOnImage)
                    .labelStyle(.iconOnly)
                    .help("Draw on Image")
            }
            Button("Close", systemImage: "xmark", action: close)
                .labelStyle(.iconOnly)
                .keyboardShortcut(.cancelAction)
                .help("Close (Esc)")
        }
        .buttonStyle(ImageZoomBarButtonStyle())
        .overlay {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 110)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}

/// A round button on the dark backdrop.
private struct ImageZoomBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(Circle().fill(.white.opacity(configuration.isPressed ? 0.3 : 0.16)))
            .contentShape(Circle())
    }
}

#if canImport(UIKit)
/// The picture in a scroll view that pinches and double-taps to zoom.
private struct ZoomedPicture: UIViewRepresentable {
    let image: CGImage
    let closeWhenTappedFitted: () -> Void

    func makeUIView(context: Context) -> ZoomingImageScrollView {
        let scrollView = ZoomingImageScrollView()
        scrollView.backgroundColor = .clear
        scrollView.image = UIImage(cgImage: image)
        scrollView.singleTapWhileFitted = closeWhenTappedFitted
        return scrollView
    }

    func updateUIView(_ scrollView: ZoomingImageScrollView, context: Context) {
        if scrollView.image?.cgImage !== image { scrollView.image = UIImage(cgImage: image) }
        scrollView.singleTapWhileFitted = closeWhenTappedFitted
    }
}
#else
/// The picture in a scroll view that magnifies with a pinch or a double-click.
private struct ZoomedPicture: View {
    let image: CGImage
    let closeWhenTappedFitted: () -> Void

    var body: some View {
        MagnifyingImageView(image: image, singleClickWhileFitted: closeWhenTappedFitted)
    }
}
#endif
