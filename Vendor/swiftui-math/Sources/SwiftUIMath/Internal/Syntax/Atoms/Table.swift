import Foundation

extension Math {
  final class Table: Atom {
    enum ColumnAlignment {
      case left
      case center
      case right
    }

    var alignments: [ColumnAlignment]
    var cells: [[AtomList]]
    var environment: String
    var interColumnSpacing: CGFloat
    var interRowAdditionalSpacing: CGFloat
    /// Graphite patch: `\hline`: the rows a horizontal rule stands before, the number of rows
    /// for one after the last, a row listed twice for a double rule.
    var horizontalRuleRows: [Int] = []
    /// Graphite patch: an array preamble's `|`: the columns a vertical rule stands before,
    /// the number of columns for one after the last, a column listed twice for a double rule.
    var verticalRuleColumns: [Int] = []
    /// Graphite patch: `\\[2pt]`: the height added above a row, in em, by row.
    var extraHeightsAboveRowsInEm: [Int: CGFloat] = [:]

    override var finalized: Math.Atom {
      let finalized = super.finalized

      if let table = finalized as? Table {
        table.cells = table.cells.map { row in
          row.map { $0.finalized }
        }
      }

      return finalized
    }

    init(_ table: Table) {
      self.alignments = table.alignments
      self.cells = table.cells.map { row in
        row.map { AtomList($0) }
      }
      self.environment = table.environment
      self.interColumnSpacing = table.interColumnSpacing
      self.interRowAdditionalSpacing = table.interRowAdditionalSpacing
      self.horizontalRuleRows = table.horizontalRuleRows
      self.verticalRuleColumns = table.verticalRuleColumns
      self.extraHeightsAboveRowsInEm = table.extraHeightsAboveRowsInEm

      super.init(table)
    }

    init(
      alignments: [ColumnAlignment] = [],
      cells: [[AtomList]] = [],
      environment: String = "",
      interColumnSpacing: CGFloat = 0,
      interRowAdditionalSpacing: CGFloat = 0
    ) {
      self.alignments = alignments
      self.cells = cells
      self.environment = environment
      self.interColumnSpacing = interColumnSpacing
      self.interRowAdditionalSpacing = interRowAdditionalSpacing
      super.init(type: .table)
    }

    func setCell(_ cell: AtomList, forRow row: Int, column: Int) {
      if cells.count <= row {
        for _ in cells.count...row {
          cells.append([])
        }
      }

      if cells[row].count <= column {
        for _ in cells[row].count...column {
          cells[row].append(AtomList())
        }
      }

      cells[row][column] = cell
    }

    func setAlignment(_ alignment: ColumnAlignment, forColumn column: Int) {
      if alignments.count <= column {
        for _ in alignments.count...column {
          alignments.append(.center)
        }
      }

      alignments[column] = alignment
    }

    func alignment(forColumn column: Int) -> ColumnAlignment {
      if alignments.count <= column {
        return .center
      }
      return alignments[column]
    }

    var numberOfColumns: Int {
      var count = 0
      for row in cells {
        count = max(count, row.count)
      }
      return count
    }

    var numberOfRows: Int {
      cells.count
    }
  }
}
