import SwiftUI

/// A source location supplied by the host after validating its rendered text.
/// Add one attribute per word; several runs of that word can share its range.
public enum ReadingSourceRangeAttribute: AttributedStringKey {
  public typealias Value = NSRange
  public static let name = "Textual.ReadingSourceRange"
}

public struct ReadingHighlightGeometry: Equatable, Sendable {
  public let sourceRange: NSRange
  public let frame: CGRect
  public init(sourceRange: NSRange, frame: CGRect) {
    self.sourceRange = sourceRange
    self.frame = frame
  }
}

/// Graphite patch 34: receives the frames of the word highlighted in each text that shows it, in place of
/// `ReadingHighlightGeometryKey`'s preference, which a lazy stack reduced over every block at every update
/// whether or not a word was read. A host gives one in the environment (`readingHighlightReceiver`).
@MainActor
public final class ReadingHighlightReceiver {
  private let receive: @MainActor ([ReadingHighlightGeometry]) -> Void
  /// The frames each text reported, by the word's range; a text whose highlight went reports none.
  private var framesByRange: [NSRange: [ReadingHighlightGeometry]] = [:]

  /// - Parameter receive: Told every frame drawn now, after each report.
  public init(_ receive: @escaping @MainActor ([ReadingHighlightGeometry]) -> Void) {
    self.receive = receive
  }

  /// The frames a text draws the word of `sourceRange` at, in the coordinate space it was given; none once it no
  /// longer draws it.
  public func report(_ frames: [ReadingHighlightGeometry], of sourceRange: NSRange) {
    guard framesByRange[sourceRange] ?? [] != frames else { return }
    framesByRange[sourceRange] = frames.isEmpty ? nil : frames
    receive(framesByRange.values.flatMap { frames in frames })
  }

  /// Every frame drawn now, as another receiver was told them: a view that reads the frames passes them on to one
  /// given around it.
  public func forward(_ frames: [ReadingHighlightGeometry]) {
    framesByRange = Dictionary(grouping: frames, by: \.sourceRange)
    receive(frames)
  }
}

extension TextualNamespace where Base: View {
  /// Draws temporary source-following highlights without replacing text selection
  /// or reparsing the attributed text on every spoken-word event.
  public func readingHighlight(_ sourceRange: NSRange?, color: Color = .yellow.opacity(0.35),
                               coordinateSpace: String? = nil) -> some View {
    base.environment(\.readingHighlightRange, sourceRange)
      .environment(\.readingHighlightColor, color)
      .environment(\.readingHighlightCoordinateSpace, coordinateSpace)
  }
}

extension AnyAttachment {
  /// Whether this is Textual's mathematical attachment, rather than an image.
  public var isMathematics: Bool { base is MathAttachment }

  /// Graphite patch: whether this draws a later piece of the formula drawn by the attachment
  /// before it; a formula a line may break inside is drawn in pieces.
  public var continuesFormula: Bool { (base as? MathAttachment)?.continuesFormula ?? false }
}

struct ReadingSourceRange: TextAttribute {
  let range: NSRange
}

extension EnvironmentValues {
  @Entry var readingHighlightRange: NSRange? = nil
  @Entry var readingHighlightColor: Color = .yellow.opacity(0.35)
  @Entry var readingHighlightCoordinateSpace: String? = nil
  /// Graphite patch 34: where a text reports the frames of its highlight; nil reports nothing.
  @Entry public var readingHighlightReceiver: ReadingHighlightReceiver? = nil
}

struct ReadingHighlight: ViewModifier {
  @Environment(\.readingHighlightRange) private var sourceRange
  @Environment(\.readingHighlightColor) private var color
  @Environment(\.readingHighlightCoordinateSpace) private var coordinateSpace
  @Environment(\.readingHighlightReceiver) private var receiver

  /// The highlight's frames in the host's coordinate space; none without one.
  private func reportedFrames(_ frames: [CGRect], sourceRange: NSRange, in geometry: GeometryProxy) -> [ReadingHighlightGeometry] {
    guard let coordinateSpace, receiver != nil else { return [] }
    let container = geometry.frame(in: .named(coordinateSpace))
    return frames.map { frame in
      ReadingHighlightGeometry(sourceRange: sourceRange, frame: frame.offsetBy(dx: container.minX, dy: container.minY))
    }
  }

  func body(content: Content) -> some View {
    content.backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
      if let sourceRange, let anchoredLayout = layouts.first {
        GeometryReader { geometry in
          let origin = geometry[anchoredLayout.origin]
          let frames = anchoredLayout.layout.flatMap { line in
            line.compactMap { run -> CGRect? in
              guard let attribute = run[ReadingSourceRange.self],
                    NSIntersectionRange(sourceRange, attribute.range).length > 0 else { return nil }
              return run.contentBounds.offsetBy(dx: origin.x, dy: origin.y)
            }
          }
          Canvas { context, _ in
            for frame in frames {
              context.fill(Path(roundedRect: frame, cornerRadius: 3), with: .color(color))
            }
          }
          .onChange(of: reportedFrames(frames, sourceRange: sourceRange, in: geometry), initial: true) { _, reported in
            receiver?.report(reported, of: sourceRange)
          }
          .onDisappear { receiver?.report([], of: sourceRange) }
          .allowsHitTesting(false)
          .accessibilityHidden(true)
        }
      }
    }
  }
}
