/**
 * File: NotePresentationScreen.swift
 * ----------------------------------
 * Layer: UI
 * Description: The device's screen while a note is presented: the slide alone, or, while another display shows
 *              the slide, the presenter's view (this slide, the next one, the slide number and the time), with the
 *              keys and the corner controls that move, choose the Pencil's tool and end.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import SwiftUI
import GraphiteCore

/// The device's screen during a presentation (decision 8): the slide full screen, or the presenter's view while
/// the slide is also on another display.
struct NotePresentationScreen: View {
    let presentation: NotePresentation
    /// Ends the presentation and closes what shows it.
    let end: () -> Void
    @FocusState private var hasKeyboardFocus: Bool

    var body: some View {
        Group {
            if presentation.hasAudienceDisplay {
                PresenterView(presentation: presentation, end: end)
            } else {
                SlideAloneView(presentation: presentation, end: end)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeyboardFocus)
        .onKeyPress(phases: .down) { keyPress in
            guard let request = PresentationKeys.request(for: keyPress.key, modifiers: keyPress.modifiers) else { return .ignored }
            perform(request)
            return .handled
        }
        .onAppear { hasKeyboardFocus = true }
        .persistentSystemOverlays(.hidden)
        #if canImport(UIKit)
        .statusBarHidden()
        #endif
    }

    private func perform(_ request: PresentationRequest) {
        switch request {
        case .move(let move): presentation.move(move)
        case .end: end()
        }
    }
}

/// The slide shown on the device, with what touches it: the Pencil's marks and a finger's moves on the iPad and
/// the iPhone, a click forward on the Mac.
struct PresentedSlide: View {
    let presentation: NotePresentation
    let content: PresentedSlideContent?
    #if canImport(UIKit)
    @AppStorage(PDFAnnotationPreferenceKey.drawsWithFinger) private var drawsWithFinger = false
    #endif

    var body: some View {
        NoteSlideView(content: content, root: presentation.root)
            #if canImport(UIKit)
            .overlay {
                PresentationTouchSurface(presentation: presentation, drawsWithFinger: drawsWithFinger, idleClock: presentation.clock)
            }
            #else
            .contentShape(Rectangle())
            .onTapGesture { presentation.move(.next) }
            #endif
    }
}

/// The slide full screen, with the slide number shown for a moment after each move and a corner of controls
/// that stays faint.
private struct SlideAloneView: View {
    let presentation: NotePresentation
    let end: () -> Void

    var body: some View {
        PresentedSlide(presentation: presentation, content: presentation.currentSlide)
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                PresentationCornerControls(presentation: presentation, end: end)
                    .padding(12)
            }
            .overlay(alignment: .bottom) {
                SlideNumberFlash(presentation: presentation)
                    .padding(.bottom, 20)
            }
    }
}

/// The slide number, "3 of 12", shown for a moment after each move.
private struct SlideNumberFlash: View {
    let presentation: NotePresentation
    @State private var isShown = false
    /// How long the number stays after a move.
    static let shownDuration = Duration.milliseconds(1500)

    var body: some View {
        Text(PresentationSlideNumber.text(for: presentation.position))
            .font(.callout.monospacedDigit())
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .opacity(isShown ? 1 : 0)
            .animation(GraphiteMotion.animation(.easeInOut(duration: 0.2)), value: isShown)
            .accessibilityHidden(!isShown)
            .task(id: presentation.moveCount) {
                guard presentation.moveCount > 0 else { return }
                isShown = true
                do { try await presentation.clock.sleep(for: Self.shownDuration) } catch { return } // A newer move shows it again.
                isShown = false
            }
    }
}

/// "3 of 12", the slide shown and how many there are.
enum PresentationSlideNumber {
    static func text(for position: SlidePosition) -> String {
        position.slideCount == 0 ? "No slides" : "\(position.index + 1) of \(position.slideCount)"
    }
}

/// The controls in the corner of the slide: the Pencil's tool on the iPad, and End. Faint until touched, so the
/// audience sees the slide.
private struct PresentationCornerControls: View {
    let presentation: NotePresentation
    let end: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            #if os(iOS)
            PresentationPencilMenu(presentation: presentation)
            #endif
            Button("End Presentation", systemImage: "xmark", action: end)
                .labelStyle(.iconOnly)
                .keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .opacity(0.55)
    }
}

/// The presenter's view while another display shows the slide: this slide large, where the Pencil draws, beside
/// the next slide, the slide number, the time since the presentation started and the controls.
private struct PresenterView: View {
    let presentation: NotePresentation
    let end: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            PresentedSlide(presentation: presentation, content: presentation.currentSlide)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 14) {
                Text("Next").font(.headline).foregroundStyle(.secondary)
                Group {
                    if let nextSlide = presentation.nextSlide {
                        NoteSlideView(content: nextSlide, root: presentation.root)
                    } else {
                        Text("End of the presentation").foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .aspectRatio(NotePresentation.canvasSize.width / NotePresentation.canvasSize.height, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(PresentationSlideNumber.text(for: presentation.position))
                    .font(.title2.monospacedDigit())
                PresentationElapsedTimeText(presentation: presentation)
                    .font(.system(size: 44, weight: .medium).monospacedDigit())
                Spacer(minLength: 0)
                PresenterButtons(presentation: presentation, end: end)
            }
            .frame(width: 320)
        }
        .padding(20)
        .background(.background)
    }
}

/// The time since the presentation started, every second.
private struct PresentationElapsedTimeText: View {
    let presentation: NotePresentation

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(PresentationElapsedTime.text(for: presentation.clock.now - presentation.startedAt))
                .accessibilityLabel("Time since the start")
        }
    }
}

/// Back, Forward, the Pencil's tool and End in the presenter's view.
private struct PresenterButtons: View {
    let presentation: NotePresentation
    let end: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button("Previous Slide", systemImage: "chevron.left") { presentation.move(.previous) }
                .disabled(presentation.position.index == 0)
            Button("Next Slide", systemImage: "chevron.right") { presentation.move(.next) }
                .disabled(presentation.position.nextIndex == nil)
            #if os(iOS)
            PresentationPencilMenu(presentation: presentation)
            #endif
            Spacer(minLength: 0)
            Button("End", systemImage: "xmark", role: .cancel, action: end)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

#if os(iOS)
/// The Pencil's tool on a slide, the laser or fading ink, and the ink's colour; a choice is kept on the device for
/// the next presentation.
private struct PresentationPencilMenu: View {
    let presentation: NotePresentation
    @AppStorage(PresentationPencilTool.preferenceKey) private var storedTool = PresentationPencilTool.laser
    @AppStorage(PresentationInkColor.preferenceKey) private var storedInkColor = PresentationInkColor.red

    var body: some View {
        let marks = presentation.marks
        Menu {
            Picker("Apple Pencil", selection: Binding(get: { marks.tool }, set: { tool in marks.choose(tool); storedTool = tool })) {
                ForEach(PresentationPencilTool.allCases) { tool in
                    Label(tool.title, systemImage: tool.symbolName).tag(tool)
                }
            }
            if marks.tool == .fadingInk {
                Picker("Ink Colour", selection: Binding(get: { marks.inkColor }, set: { color in marks.choose(color); storedInkColor = color })) {
                    ForEach(PresentationInkColor.allCases) { color in
                        Label(color.title, systemImage: "circle.fill").tint(color.color).tag(color)
                    }
                }
            }
        } label: {
            Label("Apple Pencil: \(marks.tool.title)", systemImage: marks.tool.symbolName)
                .labelStyle(.iconOnly)
        }
    }
}
#endif
