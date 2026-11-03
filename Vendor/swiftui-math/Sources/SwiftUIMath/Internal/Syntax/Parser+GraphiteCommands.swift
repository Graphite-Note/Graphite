/**
 * File: Parser+GraphiteCommands.swift
 * -----------------------------------
 * Layer: Vendor (SwiftUIMath)
 * Description: Graphite patch: reading the commands and arguments the upstream parser does
 *              not know.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import CoreGraphics
import Foundation

extension Math.Parser {
  /// Graphite patch: KaTeX's heights of `\big`, `\Big`, `\bigg` and `\Bigg`, in em.
  private static let sizedDelimiterHeightsInEm: [String: CGFloat] = [
    "big": 1.2, "Big": 1.8, "bigg": 2.4, "Bigg": 3.0,
  ]

  /// Graphite patch: the classes `\mathbin` and its kin give their argument.
  private static let classCommands: [String: Math.AtomType] = [
    "mathord": .ordinary, "mathbin": .binaryOperator, "mathrel": .relation, "mathopen": .open,
    "mathclose": .close, "mathpunct": .punctuation,
  ]

  /// Graphite patch: whether `command` is one `decoratedList(forCommand:)` reads.
  static func readsDecoratedList(_ command: String) -> Bool {
    switch command {
    case "boxed", "fbox", "textcircled", "cancel", "bcancel", "xcancel", "phantom", "hphantom",
      "vphantom", "overset", "underset", "stackrel", "xrightarrow", "xleftarrow",
      "xleftrightarrow", "overrightarrow", "overleftarrow", "overleftrightarrow", "middle":
      return true
    default:
      return classCommands[command] != nil || sizedDelimiter(command) != nil
    }
  }

  /// `\big(` and its kin: the height and the class of the delimiter (`l` opens, `r` closes,
  /// `m` relates; plain `\big` is ordinary, as in KaTeX).
  private static func sizedDelimiter(_ command: String) -> (heightInEm: CGFloat, type: Math.AtomType)? {
    for (size, heightInEm) in sizedDelimiterHeightsInEm where command.hasPrefix(size) {
      switch command.dropFirst(size.count) {
      case "": return (heightInEm, .ordinary)
      case "l": return (heightInEm, .open)
      case "r": return (heightInEm, .close)
      case "m": return (heightInEm, .relation)
      default: continue
      }
    }
    return nil
  }

  /// Graphite patch: the atom for a command that `readsDecoratedList`, with its arguments
  /// read; nil after setting an error when they cannot be.
  mutating func decoratedList(forCommand command: String) -> Math.Atom? {
    typealias DecoratedList = Math.DecoratedList
    if let atomClass = Self.classCommands[command] {
      return DecoratedList(decoration: .plainGroup, type: atomClass, innerList: buildInternal(true))
    }
    if let (heightInEm, atomClass) = Self.sizedDelimiter(command) {
      return sizedDelimiter(heightInEm: heightInEm, type: atomClass, command: command)
    }
    switch command {
    case "boxed":
      return DecoratedList(decoration: .frame, innerList: buildInternal(true))
    case "fbox":
      return DecoratedList(decoration: .frame, innerList: buildTextArgument())
    case "textcircled":
      return DecoratedList(decoration: .circle, innerList: buildTextArgument())
    case "cancel", "bcancel", "xcancel":
      return DecoratedList(
        decoration: .strikeOut(isRising: command != "bcancel", isFalling: command != "cancel"),
        innerList: buildInternal(true))
    case "phantom", "hphantom", "vphantom":
      return DecoratedList(
        decoration: .phantom(keepsWidth: command != "vphantom", keepsHeight: command != "hphantom"),
        innerList: buildInternal(true))
    case "overset", "underset", "stackrel":
      let label = buildInternal(true)
      let base = buildInternal(true)
      let decorated = DecoratedList(
        decoration: .limits,
        type: command == "stackrel" ? .relation : DecoratedList.limitsClass(of: base),
        innerList: base)
      if command == "underset" { decorated.underList = label } else { decorated.overList = label }
      return decorated
    case "xrightarrow", "xleftarrow", "xleftrightarrow":
      let heads: DecoratedList.ArrowHeads =
        command == "xrightarrow" ? .right : command == "xleftarrow" ? .left : .both
      let decorated = DecoratedList(decoration: .extensibleArrow(heads), type: .relation)
      decorated.underList = readOptionalArgument()
      decorated.overList = buildInternal(true)
      return decorated
    case "overrightarrow", "overleftarrow", "overleftrightarrow":
      let heads: DecoratedList.ArrowHeads =
        command == "overrightarrow" ? .right : command == "overleftarrow" ? .left : .both
      return DecoratedList(decoration: .arrowAbove(heads), innerList: buildInternal(true))
    case "middle":
      guard let delimiter = readDelimiter(), let boundary = Math.AtomFactory.boundary(forDelimiter: delimiter) else {
        setError(.invalidDelimiter, message: "Missing or invalid delimiter for \\middle")
        return nil
      }
      let decorated = DecoratedList(decoration: .middleDelimiter)
      decorated.nucleus = boundary.nucleus
      return decorated
    default:
      return nil
    }
  }

  private mutating func sizedDelimiter(heightInEm: CGFloat, type: Math.AtomType, command: String) -> Math.Atom? {
    guard let delimiter = readDelimiter(), let boundary = Math.AtomFactory.boundary(forDelimiter: delimiter) else {
      setError(.invalidDelimiter, message: "Missing or invalid delimiter for \\\(command)")
      return nil
    }
    let decorated = Math.DecoratedList(decoration: .sizedDelimiter(heightInEm: heightInEm), type: type)
    decorated.nucleus = boundary.nucleus
    return decorated
  }

  /// One argument read as `\text` reads it: upright, with its spaces.
  private mutating func buildTextArgument() -> Math.AtomList? {
    let outerFontStyle = currentFontStyle
    let outerSpacesAllowed = spacesAllowed
    currentFontStyle = .roman
    spacesAllowed = true
    defer {
      currentFontStyle = outerFontStyle
      spacesAllowed = outerSpacesAllowed
    }
    return buildInternal(true)
  }

  /// The argument in `[…]` after a command, or nil when there is none.
  private mutating func readOptionalArgument() -> Math.AtomList? {
    skipSpaces()
    guard hasCharacters, string[currentCharIndex] == "[" else { return nil }
    _ = nextCharacter()
    return buildInternal(false, stopChar: "]")
  }

  /// Graphite patch: the columns of an array's preamble (`{l|cc}`). `p{…}`, `m{…}` and `b{…}`
  /// columns are left-aligned; `@{…}`, `!{…}` and the dashed `:` are skipped. Nil, with an
  /// error set, when there is no preamble.
  mutating func readArrayPreamble() -> (alignments: [Math.Table.ColumnAlignment], verticalRuleColumns: [Int])? {
    guard expectCharacter("{") else {
      setError(.characterNotFound, message: "Missing array preamble")
      return nil
    }
    var alignments: [Math.Table.ColumnAlignment] = []
    var verticalRuleColumns: [Int] = []
    while hasCharacters {
      let character = nextCharacter()
      switch character {
      case "}":
        return (alignments, verticalRuleColumns)
      case "|":
        verticalRuleColumns.append(alignments.count)
      case "l":
        alignments.append(.left)
      case "c":
        alignments.append(.center)
      case "r":
        alignments.append(.right)
      case "p", "m", "b":
        alignments.append(.left)
        skipGroup()
      case "@", "!":
        skipGroup()
      default:
        // `:`, spaces
        continue
      }
    }
    setError(.mismatchedBraces, message: "Missing } after array preamble")
    return nil
  }

  /// Skips a braced group after optional spaces, with the groups nested in it.
  private mutating func skipGroup() {
    skipSpaces()
    guard hasCharacters, string[currentCharIndex] == "{" else { return }
    var depth = 0
    while hasCharacters {
      switch nextCharacter() {
      case "{": depth += 1
      case "}":
        depth -= 1
        if depth == 0 { return }
      default: continue
      }
    }
  }

  /// A row break's optional length (`[2pt]`), written right after it, in em, read past.
  /// Nil when there is none: brackets that do not hold a length, as in `\\[a,b]`, are the
  /// next row's.
  mutating func readRowBreakLengthInEm() -> CGFloat? {
    guard hasCharacters, string[currentCharIndex] == "[" else { return nil }
    let lengthStart = string.index(after: currentCharIndex)
    guard let lengthEnd = string[lengthStart...].firstIndex(of: "]"),
      let lengthInMu = Self.lengthInMu(String(string[lengthStart..<lengthEnd]))
    else { return nil }
    currentCharIndex = string.index(after: lengthEnd)
    return lengthInMu / Self.muPerEm
  }

  /// `\hspace{…}` as a space. A length that cannot be read is an error.
  mutating func horizontalSpace() -> Math.Atom? {
    guard expectCharacter("{") else {
      setError(.characterNotFound, message: "Missing { after \\hspace")
      return nil
    }
    var length = ""
    while hasCharacters {
      let character = nextCharacter()
      if character == "}" { break }
      length.append(character)
    }
    guard let lengthInMu = Self.lengthInMu(length) else {
      setError(.invalidCommand, message: "Invalid length \(length) for \\hspace")
      return nil
    }
    return Math.Space(amount: lengthInMu)
  }

  private static let muPerEm: CGFloat = 18

  /// A TeX length in mu, at a 10 pt font, where 1 em is 10 pt and 18 mu; nil when `text` is not
  /// a number and a unit.
  private static func lengthInMu(_ text: String) -> CGFloat? {
    let length = text.filter { character in !character.isWhitespace }
    let numberText = length.prefix { character in character.isNumber || "+-.".contains(character) }
    let muPerUnit: [Substring: CGFloat] = [
      "em": muPerEm, "ex": 7.74, "mu": 1, "pt": 1.8, "mm": 5.12, "cm": 51.2, "in": 130, "bp": 1.81, "pc": 21.6,
    ]
    guard let number = Double(numberText), let muPerLength = muPerUnit[length.dropFirst(numberText.count)] else {
      return nil
    }
    return CGFloat(number) * muPerLength
  }

  /// Graphite patch: `\operatorname*{name}`, an upright operator with limits, as `\lim` is.
  /// A name that is not plain letters is drawn upright, without limits.
  mutating func operatorWithLimits() -> Math.Atom? {
    skipSpaces()
    let argumentStart = currentCharIndex
    if hasCharacters, nextCharacter() == "{" {
      var name = ""
      while hasCharacters {
        let character = nextCharacter()
        if character == "}" {
          if !name.isEmpty { return Math.AtomFactory.operatorWithName(name, limits: true) }
          break
        }
        if character == "\\", hasCharacters, ",;:> ".contains(string[currentCharIndex]) {
          // A small space, as in `arg\,max`.
          _ = nextCharacter()
          name.append(" ")
          continue
        }
        guard (character.isASCII && character.isLetter) || character == " " else { break }
        if character != " " { name.append(character) }
      }
    }
    currentCharIndex = argumentStart
    let outerFontStyle = currentFontStyle
    currentFontStyle = .roman
    defer { currentFontStyle = outerFontStyle }
    return Math.DecoratedList(decoration: .plainGroup, innerList: buildInternal(true))
  }
}
