/**
 * File: NotePresentation.swift
 * ----------------------------
 * Layer: UI
 * Description: One note presented as slides: its slides, each built by the reading view's builder off the main
 *              actor, the slide shown, the time since the presentation started, and the Pencil's tool on it.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import SwiftUI
import GraphiteCore
import GraphiteIndex

/// What a slide shows while its blocks are built, once they are, or why they could not be.
enum PresentedSlideContent {
    case building
    case built([RenderedBlock])
    /// The slide's blocks could not be built; the slide says so.
    case failed
}

/// The note's text, read once when the presentation starts, and the vault its slides are built in.
struct NotePresentationSource {
    let text: String
    let path: VaultPath
    let root: URL
    let index: VaultIndex
    /// The reading view's settings that change how a slide is built (line breaks, colours, property types).
    let configuration: ReadingConfiguration
}

/// One note presented as slides (Docs/Present-a-note-todo.md). It reads the note's text once, when it starts,
/// and writes nothing. Its slides are built in order, the first at once, by the task it owns; `end()` cancels
/// that task and releases the slides.
@MainActor @Observable
final class NotePresentation: Identifiable {
    /// The fixed shape every slide is laid out at, scaled to each screen, so the device and an external display
    /// show the same layout and the Pencil's marks land on the same words (decision 3).
    nonisolated static let canvasSize = CGSize(width: 1280, height: 720)
    /// The text size slides are built and laid out at, on `canvasSize`.
    nonisolated static let slideTextSize: Double = 32

    let id = UUID()
    /// The note's name, shown in the presenter's view.
    let title: String
    let root: URL
    private(set) var slides: [PresentedSlideContent]
    private(set) var position: SlidePosition
    /// When the presentation started, on `clock`.
    let startedAt: Duration
    let clock: any ApplicationClock
    /// Counts the moves between slides, so the slide number shows for a moment after each one.
    private(set) var moveCount = 0
    /// True once `end()` has run: the views that show the presentation close.
    private(set) var hasEnded = false
    /// Whether the slide is also shown on another display, which makes the device's screen the presenter's view.
    private(set) var hasAudienceDisplay = false
    private var buildTask: Task<Void, Never>?
    #if canImport(UIKit)
    /// The Pencil's marks on the slide, shown on every screen that shows it, cleared when the slide changes.
    let marks: PresentationMarks
    #endif

    init(title: String, root: URL, slideCount: Int, clock: any ApplicationClock, pencil: PresentationPencilChoices) {
        self.title = title
        self.root = root
        slides = Array(repeating: .building, count: slideCount)
        position = SlidePosition(slideCount: slideCount)
        self.clock = clock
        startedAt = clock.now
        #if canImport(UIKit)
        marks = PresentationMarks(choices: pencil)
        #endif
    }

    /// A presentation of `source`'s slides, which start building at once.
    static func started(from source: NotePresentationSource, clock: any ApplicationClock, pencil: PresentationPencilChoices) -> NotePresentation {
        let slides = NoteSlides.slides(in: source.text)
        let presentation = NotePresentation(title: source.path.stem, root: source.root, slideCount: slides.count, clock: clock, pencil: pencil)
        presentation.startBuilding(slides, of: source)
        return presentation
    }

    var currentSlide: PresentedSlideContent? { slides.indices.contains(position.index) ? slides[position.index] : nil }
    var nextSlide: PresentedSlideContent? { position.nextIndex.map { index in slides[index] } }

    func move(_ move: SlideMove) {
        guard !hasEnded, position.apply(move) else { return }
        moveCount += 1
        #if canImport(UIKit)
        marks.clear()
        #endif
    }

    /// Records whether another display shows the slide, as displays connect and disconnect.
    func setAudienceDisplay(isShown: Bool) {
        guard hasAudienceDisplay != isShown else { return }
        hasAudienceDisplay = isShown
    }

    /// Ends the presentation: its building stops and its slides are released. The note is as it was.
    func end() {
        guard !hasEnded else { return }
        hasEnded = true
        buildTask?.cancel()
        buildTask = nil
        slides = []
        position = SlidePosition(slideCount: 0)
        #if canImport(UIKit)
        marks.clear()
        #endif
    }

    /// Builds each slide as the reading view builds a note, in order, off the main actor (`ReadingViewBuilder`).
    private func startBuilding(_ noteSlides: [NoteSlide], of source: NotePresentationSource) {
        let configuration = Self.slideConfiguration(from: source.configuration)
        buildTask = Task { [weak self] in
            for (slideIndex, noteSlide) in noteSlides.enumerated() {
                let content: PresentedSlideContent
                do {
                    let build = try await ReadingViewBuilder().build(source: noteSlide.markdown, note: source.path, root: source.root,
                                                                     index: source.index, configuration: configuration)
                    content = .built(build.blocks)
                } catch is CancellationError {
                    return
                } catch {
                    content = .failed
                }
                guard let self, !Task.isCancelled else { return }
                self.slides[slideIndex] = content
            }
        }
    }

    /// The reading configuration a slide is built with: the note's own, at the slide's text size, without the
    /// properties panel and the inline title, which a slide does not show.
    static func slideConfiguration(from noteConfiguration: ReadingConfiguration) -> ReadingConfiguration {
        var configuration = noteConfiguration
        configuration.showsProperties = false
        configuration.inlineTitle = nil
        configuration.textSize = slideTextSize
        configuration.mapsReadAloudSourceLocations = false
        configuration.runsPluginPostProcessors = false
        configuration.usesReadableLineLength = false
        return configuration
    }
}
