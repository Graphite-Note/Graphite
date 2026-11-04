/**
 * File: Math+SymbolClass.swift
 * ----------------------------
 * Layer: Vendor (SwiftUIMath)
 * Description: Graphite patch: the TeX class of a symbol, from the typesetter's own tables, so
 *              Textual can find where a line may break inside inline math.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 04/11/2026
 */

extension Math {
  /// The TeX class of a symbol: what decides the spacing around it and where a line may break
  /// after it.
  @_spi(Textual)
  public enum SymbolClass: Sendable {
    /// A letter, digit or other ordinary symbol (Ord in TeX).
    case ordinary
    /// A large operator such as `\sum` or `\sin` (Op).
    case largeOperator
    /// A binary operator such as `+` or `\cdot` (Bin).
    case binaryOperator
    /// A relation such as `=` or `\parallel` (Rel).
    case relation
    /// An opening bracket (Open).
    case open
    /// A closing bracket (Close).
    case close
    /// A comma or semicolon (Punct).
    case punctuation
  }

  /// The class of the command `\name` (`name` without its backslash), as the typesetter sets
  /// it; nil when the command is not a symbol (a fraction, an accent, a space, unknown).
  /// Nonisolated, though `Math` is a view: it reads only the typesetter's tables, which are
  /// constants or behind a lock, and Textual asks from any thread.
  @_spi(Textual)
  public nonisolated static func symbolClass(ofCommand name: String) -> SymbolClass? {
    AtomFactory.atom(forLatexSymbol: name).flatMap { atom in SymbolClass(atom.type) }
  }

  /// The class of a character written as itself in a formula; nil when it is not a symbol on
  /// its own (`^`, `{`, a space).
  @_spi(Textual)
  public nonisolated static func symbolClass(ofCharacter character: Character) -> SymbolClass? {
    AtomFactory.atom(forCharacter: character).flatMap { atom in SymbolClass(atom.type) }
  }
}

extension Math.SymbolClass {
  fileprivate init?(_ type: Math.AtomType) {
    switch type {
    case .ordinary, .number, .variable, .unaryOperator: self = .ordinary
    case .largeOperator: self = .largeOperator
    case .binaryOperator: self = .binaryOperator
    case .relation: self = .relation
    case .open: self = .open
    case .close: self = .close
    case .punctuation: self = .punctuation
    default: return nil
    }
  }
}
