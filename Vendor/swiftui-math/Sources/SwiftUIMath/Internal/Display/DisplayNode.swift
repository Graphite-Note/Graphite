import CoreGraphics
import Foundation

extension Math {
  class DisplayNode {
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    var width: CGFloat = 0
    var position: CGPoint = .zero
    var range: NSRange = NSRange(location: 0, length: 0)
    var hasScript: Bool = false
    var textColor: CGColor?
    var localTextColor: CGColor?
    /// Graphite patch: this node and what it holds draw in the formula's text color, whatever
    /// color they stand in.
    var resetsToTextColor: Bool = false
    var localBackgroundColor: CGColor?

    var bounds: CGRect {
      CGRect(x: position.x, y: position.y - descent, width: width, height: ascent + descent)
    }

    /// Graphite patch: the color of `\textcolor` or `\color`, its argument read as MathJax reads it.
    func setTextColor(forArgument argument: String) {
      resetsToTextColor = FormulaColor.isTextColor(argument: argument)
      localTextColor = resetsToTextColor ? nil : FormulaColor.color(forArgument: argument)
    }
  }
}
