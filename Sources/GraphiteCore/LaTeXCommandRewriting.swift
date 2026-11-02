/**
 * File: LaTeXCommandRewriting.swift
 * ---------------------------------
 * Layer: Core
 * Description: One walk over a formula that rewrites what the typesetter reads otherwise than
 *              MathJax: declarations that last to the end of a group, and commands it knows
 *              under another name.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import Foundation

/// MathJax's `\color{…}` and the font declarations change the remainder of their group, and a
/// cell of an environment or a `\left…\right` pair is a group; the native typesetter instead
/// consumes just one following atom. The walk converts declarations to explicit groups, closing
/// them where the group ends: before the enclosing brace, `\end` or `\right`, or at the `&` or
/// `\\` that ends the cell. Nested declarations override their parent color without leaking out
/// of their group. The typesetter also lacks `\operatorname`; upright names use `\mathrm`.
/// Starred operators, which need limit placement, it reads itself.
struct LaTeXCommandRewriting {
    /// Three low dots as TeX sets `\ldots`, 3 mu apart; the math font's `…` has them closer.
    private static let lowDots = "{.\\,.\\,.}"

    /// Commands the typesetter knows under another name, or that it draws no differently:
    /// each is replaced by this text. Sizes (`\small`) and `\smash` draw nothing of their own here.
    private static let commandAliases: [String: String] = [
        "boldsymbol": "\\bm", "pmb": "\\bm",
        "lvert": "\\vert", "rvert": "\\vert", "lVert": "\\Vert", "rVert": "\\Vert",
        "lbrack": "[", "rbrack": "]", "textbar": "|", "textless": "<", "textgreater": ">",
        "mathscr": "\\mathcal", "textnormal": "\\textrm", "mbox": "\\text", "hbox": "\\text",
        "dag": "\\dagger", "ddag": "\\ddagger", "textdegree": "\\degree", "textmu": "\\mu",
        "ldots": lowDots, "dotsc": lowDots, "dotso": lowDots, "dotsb": "\\cdots", "dotsm": "\\cdots", "dotsi": "\\cdots",
        "thinspace": "\\,", "medspace": "\\>", "thickspace": "\\;", "negthinspace": "\\!", "enspace": "\\>\\;",
        "shortparallel": "\\parallel", "shortmid": "\\mid",
        "bmod": "\\mathbin{\\mathrm{mod}}", "sp": "^", "sb": "_",
        "varGamma": "\\mathit{\\Gamma}", "varDelta": "\\mathit{\\Delta}", "varTheta": "\\mathit{\\Theta}",
        "varLambda": "\\mathit{\\Lambda}", "varXi": "\\mathit{\\Xi}", "varPi": "\\mathit{\\Pi}",
        "varSigma": "\\mathit{\\Sigma}", "varUpsilon": "\\mathit{\\Upsilon}", "varPhi": "\\mathit{\\Phi}",
        "varPsi": "\\mathit{\\Psi}", "varOmega": "\\mathit{\\Omega}",
        "tiny": "", "scriptsize": "", "footnotesize": "", "small": "", "normalsize": "", "large": "",
        "Large": "", "LARGE": "", "huge": "", "Huge": "", "smash": "",
    ]

    /// Font declarations, which last to the end of their group; the typesetter's commands
    /// for these fonts take one argument.
    private static let fontDeclarations: [String: String] = [
        "rm": "\\mathrm", "bf": "\\mathbf", "it": "\\mathit", "sf": "\\mathsf", "tt": "\\mathtt", "cal": "\\mathcal",
    ]

    /// amsmath's `\dots` is centered before these, binary operators and relations, and low
    /// otherwise.
    private static let commandsAfterCenteredDots: Set<String> = [
        "cdot", "times", "pm", "mp", "ast", "circ", "bullet", "oplus", "otimes", "cup", "cap", "wedge", "vee", "land", "lor",
        "leq", "le", "geq", "ge", "neq", "ne", "equiv", "approx", "sim", "simeq", "cong", "to", "rightarrow", "leftarrow",
        "Rightarrow", "Leftarrow", "implies", "iff", "subset", "subseteq", "supset", "supseteq", "in",
    ]
    private static let charactersAfterCenteredDots: Set<Character> = ["+", "-", "=", "<", ">"]

    /// How far one level of a formula reaches, for a declaration that lasts to the end of it.
    private struct DeclarationScope {
        /// Braces the walk opened for declarations at this level, to close at its end.
        var openDeclarations = 0
        /// A cell of an environment, which `&` and `\\` end, as they end a TeX group.
        var isEnvironment = false
    }

    private let characters: [Character]
    private var output = ""
    private var scopes = [DeclarationScope()]
    private var position = 0

    private init(_ latex: String) {
        characters = Array(latex)
    }

    /// `latex` as the typesetter can read it.
    static func rewriting(_ latex: String) -> String {
        var rewriting = LaTeXCommandRewriting(latex)
        rewriting.walk()
        return rewriting.output
    }

    private mutating func walk() {
        while position < characters.count {
            let character = characters[position]
            if character == "\\", position + 1 < characters.count {
                rewriteCommand()
                continue
            }
            if character == "{" {
                scopes.append(DeclarationScope())
            } else if character == "}" {
                leaveScope()
            } else if character == "&", scopes[scopes.count - 1].isEnvironment {
                closeScopeDeclarations()
            }
            output.append(character)
            position += 1
        }
        // Leave malformed, unclosed source groups for the typesetter to reject.
        if scopes.count == 1 {
            closeScopeDeclarations()
        }
    }

    /// Ends the innermost scope; the outermost one lasts to the end of the formula.
    private mutating func leaveScope() {
        guard scopes.count > 1 else { return }
        closeScopeDeclarations()
        scopes.removeLast()
    }

    private mutating func closeScopeDeclarations() {
        output += String(repeating: "}", count: scopes[scopes.count - 1].openDeclarations)
        scopes[scopes.count - 1].openDeclarations = 0
    }

    /// Rewrites the command at `position`, a backslash with something after it.
    private mutating func rewriteCommand() {
        let commandStart = position
        position += 1
        while position < characters.count, characters[position].isASCII, characters[position].isLetter {
            position += 1
        }
        if position == commandStart + 1 {
            rewriteEscapedSymbol(startingAt: commandStart)
            return
        }
        let command = String(characters[(commandStart + 1)..<position])
        var argumentStart = position
        while argumentStart < characters.count, characters[argumentStart].isWhitespace { argumentStart += 1 }
        let hasBracedArgument = argumentStart < characters.count && characters[argumentStart] == "{"

        if command == "color", hasBracedArgument, openColorDeclaration(argumentStart: argumentStart) {
            return
        } else if command == "operatorname", hasBracedArgument {
            output += "\\mathrm"
        } else if command == "begin", hasBracedArgument, let nameEnd = characters[(argumentStart + 1)...].firstIndex(of: "}") {
            output += String(characters[commandStart...nameEnd])
            position = nameEnd + 1
            scopes.append(DeclarationScope(isEnvironment: true))
        } else if command == "end" || command == "right" {
            leaveScope()
            output += String(characters[commandStart..<position])
        } else if command == "left" {
            output += String(characters[commandStart..<position])
            scopes.append(DeclarationScope())
        } else if let font = Self.fontDeclarations[command] {
            output += font + "{"
            scopes[scopes.count - 1].openDeclarations += 1
        } else if command == "dots" {
            output += isBinaryOrRelation(at: argumentStart) ? "\\cdots" : Self.lowDots
        } else if let alias = Self.commandAliases[command] {
            output += alias
        } else {
            output += String(characters[commandStart..<position])
        }
    }

    /// A backslash and a character that is not a letter. Escaped braces and row breaks are not
    /// group boundaries, but a row break ends a cell. The typesetter knows `\:` as `\>`.
    private mutating func rewriteEscapedSymbol(startingAt commandStart: Int) {
        let symbol = characters[position]
        if symbol == "\\", scopes[scopes.count - 1].isEnvironment { closeScopeDeclarations() }
        output += symbol == ":" ? "\\>" : String(characters[commandStart...position])
        position += 1
    }

    /// `\color{…}` as an explicit group, when the argument at `argumentStart` is a plain name.
    private mutating func openColorDeclaration(argumentStart: Int) -> Bool {
        guard let argumentEnd = characters[(argumentStart + 1)...].firstIndex(of: "}"),
              !characters[(argumentStart + 1)..<argumentEnd].contains("{") else { return false }
        output += "\\textcolor" + String(characters[argumentStart...argumentEnd]) + "{"
        scopes[scopes.count - 1].openDeclarations += 1
        position = argumentEnd + 1
        return true
    }

    /// Whether a binary operator or a relation starts at `offset`, as far as `\dots` looks.
    private func isBinaryOrRelation(at offset: Int) -> Bool {
        guard offset < characters.count else { return false }
        guard characters[offset] == "\\" else { return Self.charactersAfterCenteredDots.contains(characters[offset]) }
        var nameEnd = offset + 1
        while nameEnd < characters.count, characters[nameEnd].isASCII, characters[nameEnd].isLetter { nameEnd += 1 }
        return Self.commandsAfterCenteredDots.contains(String(characters[(offset + 1)..<nameEnd]))
    }
}
