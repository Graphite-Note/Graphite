import SwiftUI

/// Graphite addition: marks a paragraph whose lines each stay on one line, cut with an ellipsis
/// at the end when wider than the paragraph, as Notion draws its links to pages. A host sets it
/// on the paragraph's runs; ``StructuredText`` then draws each of the paragraph's lines (its
/// hard line breaks) as a text of its own, limited to one line.
public enum TruncatedLinesAttribute: AttributedStringKey {
  public typealias Value = Bool
  public static let name = "Textual.TruncatedLines"
}

/// The lines of a paragraph marked with ``TruncatedLinesAttribute``, one text each, spaced by the
/// paragraph's line spacing so that lines short enough to fit stand where one text would put them, within a pixel.
struct TruncatedLines: View {
  @Environment(\.lineSpacing) private var lineSpacing

  let content: AttributedString

  var body: some View {
    VStack(alignment: .leading, spacing: lineSpacing) {
      ForEach(Array(Self.lines(of: content).enumerated()), id: \.offset) { _, line in
        TextFragment(line)
          .lineLimit(1)
          .truncationMode(.tail)
      }
    }
  }

  /// The text between the hard line breaks (`\n`) of `content`, each break left out.
  static func lines(of content: AttributedString) -> [AttributedString] {
    var lines: [AttributedString] = []
    var lineStart = content.startIndex
    var index = content.startIndex
    while index < content.endIndex {
      let next = content.characters.index(after: index)
      if content.characters[index] == "\n" {
        lines.append(AttributedString(content[lineStart..<index]))
        lineStart = next
      }
      index = next
    }
    lines.append(AttributedString(content[lineStart..<content.endIndex]))
    return lines
  }

  /// Whether `content` is marked to keep each of its lines on one line.
  static func isMarked(_ content: some AttributedStringProtocol) -> Bool {
    content.runs.contains { run in run[TruncatedLinesAttribute.self] == true }
  }
}
