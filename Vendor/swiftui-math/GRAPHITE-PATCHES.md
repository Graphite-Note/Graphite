# Graphite changes to SwiftUIMath 0.1.0

Upstream: https://github.com/gonzalezreal/swiftui-math at tag 0.1.0 (commit 0b5c2cfaaec8d6193db206f675048eeb5ce95f71). License: MIT (see LICENSE); the math fonts in `Sources/SwiftUIMath/mathFonts.bundle` carry their own licenses (`OFL.txt`, `GUST-FONT-LICENSE.txt`, `LICENSE` there). Upstream tests, snapshots and the demo images are not vendored, so the manifest has no test target and no SnapshotTesting dependency. Graphite reaches this package only through its vendored Textual (`Vendor/textual/Package.swift`).

## 1. A formula is not broken into lines by its rounded frame

`Sources/SwiftUIMath/Internal/Display/DisplayProvider.swift`: `display(for:font:style:proposedWidth:)` typesets a formula on one line when it is wider than the proposed width by at most `lineBreakTolerance` (one point), and breaks it into lines only when it is wider than that.

`Math` measures its formula for the width it is offered, then draws it in a `Canvas` that typesets the formula again at the canvas's own width. That frame is rounded to whole pixels, so it can come out a fraction of a point narrower than the formula it was measured for. Upstream then broke the formula to fit: `g_m` became `g` over `m` (at 22 points, half a point too narrow is enough; `r_o`, `V_A` and `V_{ov}` break at a quarter of a point), and only one of the two lines showed where the formula belonged. In Graphite's reading view, inline formulas such as `$g_m$`, `$r_o$` and `$V_A$` showed only their subscripts, in some paragraphs and not others, since the rounding depends on where the formula lands. Rounding moves each edge of a frame by at most half a pixel, so a frame is at most one pixel (one point at 1x) narrower than asked, which the tolerance covers at every scale. Textual allows display math the same overhang (`MathAttachment.naturalWidthTolerance`).

Regression test: `AppProjectTextualPatchTests.testFormulaInAFrameNarrowerByAFractionOfAPointStaysOnOneLine` draws each formula in a frame 0.4 points narrower than it and checks that it stays on one line, and that a formula genuinely wider than its width still breaks.

## 2. A fraction late in a line breaks onto the next line

`Sources/SwiftUIMath/Internal/Display/Typesetter.swift`: `shouldBreakBeforeDisplay` measures the line from its start, `currentPosition.x` plus the text since the last display, as the interatom check already does, and treats a line that holds only earlier displays as not empty. Upstream measured only the text since the last fraction, radical or other display, so a fraction after earlier ones was never moved to a new line and was drawn past the width. In a callout, `\text{new time} = \frac{1-f}{s} + f, \qquad \text{memory share} = \frac{f}{…}, \qquad \text{overall speedup} = \frac{1}{\frac{1-f}{s} + f}` at 95 % of its width was not broken at all, and the last fraction was cut off at the callout's edge.

Regression test: `AppProjectTextualPatchTests.testFractionAfterEarlierFractionsBreaksOntoANewLine` measures that formula at 95, 80 and 60 % of its width and checks that it is broken into lines no wider than the width.

## 3. `\underbrace` and `\overbrace`

`Sources/SwiftUIMath/Internal/Syntax/Atoms/HorizontalBrace.swift` and `Internal/Display/DisplayHorizontalBrace.swift` (new), `Internal/Syntax/AtomList.swift`, `Internal/Syntax/Parser.swift`, `Internal/Display/Typesetter.swift`, `Internal/Display/CGContext+DisplayNode.swift`: `\underbrace{…}_{label}` and `\overbrace{…}^{label}` are typeset. Upstream did not know either command, so a formula using one could not be parsed and Graphite showed its LaTeX source (Textual patch 5).

The brace is drawn as a stroked path as wide as what it spans: the math fonts' brace glyphs come in a few fixed widths (Latin Modern's widest is 4 em) and the font tables carry no horizontal assembly to build a longer one. Its proportions follow Latin Modern's glyph, about 0.32 em tall and 0.06 em thick, and it stands 0.2 em from what it spans. The label is set in script style below an underbrace or above an overbrace, centred, with the gaps of an operator's limits (`DisplayLargeOperator`); the other script, if any, is an ordinary script at the right. A brace is an ordinary atom for spacing and line breaking.

## 4. A hyphen in `\text` is a hyphen

`Sources/SwiftUIMath/Internal/Syntax/Parser.swift`: inside `\text{…}`, `-` is an ordinary hyphen. Upstream turned it into a minus sign with a binary operator's spaces, so `\text{wear-out}` read "wear − out". A `-` outside `\text` is still a minus.

Regression tests: `AppProjectTextualPatchTests.testUnderbraceAndOverbraceAreTypesetWithTheirLabels` and `testHyphenInsideTextIsAHyphen`.

## 5. A formula is drawn as shapes, not into a `Canvas`

`Sources/SwiftUIMath/Math.swift`, `Internal/Display/DisplayNode+Outlines.swift`: `Math` shows a formula as SwiftUI `Path` shapes, one per color, filled with the foreground style (or, in multicolor mode, the formula's own colors and the base color). `MathOutlines` walks the display tree as `CGContext.draw(_:foregroundColor:)` does, turning each glyph into its outline (`CTFontCreatePathForGlyph`, and Core Text's glyph runs for text) and each rule, radical bar and brace into the area its stroke covers. SwiftUI draws a `Canvas` through RenderBox, which starts a Metal device that held about 200 MB of graphics memory while a note with formulas scrolled. The outlines are vector, so a formula stays sharp in a PDF. On the Mac the outlines are also stroked by 1.4 % of the font size (`Math.glyphThickening`), because Core Text thickens glyphs as it draws them there (font smoothing) and a filled outline looked thinner: a purple formula on black at 1× had 25 and 35 fully colored pixels in its halves against 58 and 55 when Core Text drew it, and 42 to 78 with a stroke of 1.2 to 1.6 %. `CGContext+DisplayNode.swift` and `GraphicsContext+DisplayNode.swift` are no longer called; the outlines follow the first, and a change to how a node is drawn goes in both.

## 6. The TeX class of a symbol, for Textual

`Sources/SwiftUIMath/Math+SymbolClass.swift` (new): `Math.symbolClass(ofCommand:)` and `symbolClass(ofCharacter:)` (`@_spi(Textual)`) give the TeX class of a symbol (ordinary, large operator, binary operator, relation, open, close, punctuation) from the typesetter's own tables, its aliases included. Textual uses it to find where a line may break inside inline math (its patch 21) without a second list of operators. Test: `AppProjectTextualPatchTests.testInlineMathBreaksAfterOperatorsAndRelationsAtItsOuterLevelOnly`.

## 7. A space at the end of a formula counts in its width

`Sources/SwiftUIMath/Internal/Display/Typesetter.swift` (`createLineForMathList`): a list's width reaches the end of its last line, explicit spaces included, as a TeX box does. Upstream measured only its drawn parts, so `a +\>` was as wide as `a +`. Textual's pieces of inline math (its patch 21) end with their operator's space, and side by side were narrower than the formula drawn whole, the operators touching the next piece. Test: `AppProjectTextualPatchTests.testFormulaInPiecesCopiesOnceAndKeepsItsWidth`.

## 8. KaTeX's other arrows

`Sources/SwiftUIMath/Internal/Syntax/AtomFactory.swift`: the arrows KaTeX lists beyond the plain ones are relations, each drawn with its Unicode arrow, for every arrow Latin Modern Math has a glyph for: the squiggly arrows (`\rightsquigarrow`, `\leadsto`, `\leftrightsquigarrow`), hooks, tails, loops, curves and circles, harpoons and their pairs (`\rightleftharpoons`), doubled and tripled arrows, the struck-through arrows (`\nrightarrow`, `\nRightarrow`, …), `\Lsh`, `\Rsh`, `\multimap`, `\longmapsto`, and the aliases `\impliedby` and `\restriction`. Upstream knew only the plain arrows, so a formula with any of these could not be parsed and Graphite showed its LaTeX source: a figure caption's `$R_G \rightsquigarrow R_G/4$` read as source in the reading view. The dashed arrows (`\dashrightarrow`, `\dashleftarrow`) are left out: Latin Modern has no glyph for them.

Regression test: `AppProjectTextualPatchTests.testKaTeXArrowsAreTypesetAsOneRelation` typesets each arrow between two letters and checks it is about as wide as `\rightarrow`, and that the caption's formula becomes one attachment.

## 10. Characters typed in a formula

`Sources/SwiftUIMath/Internal/Syntax/Parser.swift`, `AtomFactory.swift` (`atom(forTypedCharacter:)`): a character that is not ASCII is drawn as the command that has it as its symbol, with that command's class (`≤` is `\leq`, `δ` is `\delta`), and otherwise as an upright ordinary atom, which the font or a fallback font draws, as MathJax draws it. Upstream dropped such characters in math, so `$δ$` could not be typeset and `$κ(x)$` lost its `κ`. Spaces and invisible characters are still skipped. A command's name is ASCII letters, as in TeX, so `\cosθ` is `\cos` and `θ`; upstream read one unknown command. `\&` is an ampersand, and a backslash before a line break is a space.

Regression test: `AppProjectTextualPatchTests.testCharactersTypedInAFormulaAreDrawnAsTheirCommands`.

## 11. KaTeX's other symbols

`Sources/SwiftUIMath/Internal/Syntax/AtomFactory.swift`, `Parser.swift` (`notCombinations`): relations (`\leqslant`, `\geqslant`, `\lesssim`, `\gtrsim`, `\preceq`, `\succeq`, `\triangleq`, `\therefore`, `\vdash`, `\subsetneq`, `\nmid`, …), binary operators (`\diamond`, `\bigcirc`, `\circledast`, `\barwedge`, `\ltimes`, `\triangleleft`, …), ordinary symbols (`\blacksquare`, `\varnothing`, `\checkmark`, `\lozenge`, `\complement`, `\sharp`, `\S`, …), the delimiters `\llbracket` and `\rrbracket`, the operators `\oiint` and `\oiiint`, the accents `\mathring`, `\dddot` and `\ddddot`, and `\not` before `\leq`, `\geq`, `\prec`, `\succ` and `\mid`. Each glyph was checked to exist in Latin Modern Math, except `\bigstar` and `\blacklozenge`, which it lacks and Core Text draws with a fallback font.

Regression test: `AppProjectTextualPatchTests.testKaTeXSymbolsAreTypesetInTheirClasses`.

## 12. Decorated lists: frames, strike-outs, phantoms, labels, stretched arrows, sized delimiters

`Sources/SwiftUIMath/Internal/Syntax/Atoms/DecoratedList.swift`, `Internal/Syntax/Parser+GraphiteCommands.swift`, `Internal/Display/Typesetter+DecoratedList.swift`, `Internal/Display/DisplayStroke.swift` (new), `Internal/Syntax/AtomList.swift`, `Internal/Syntax/Parser.swift`, `Internal/Display/Typesetter.swift`, `Internal/Display/CGContext+DisplayNode.swift`, `Internal/Display/DisplayNode+Outlines.swift`. One atom, `DecoratedList`, stands for these commands; upstream knew none, so a formula using one showed as its source. Its type is the TeX class it spaces and breaks as, so the rules that read classes (a minus after a relation is a sign) need no change, and the typesetter recognizes it by its Swift class before it looks at the type.

- `\boxed` and `\fbox`: a rectangle 0.3 em from what it holds, its lines 0.04 em (`\fboxsep`, `\fboxrule`). `\boxed` sets its content in display style, as amsmath does; `\fbox` holds text. `\textcircled` draws a circle, at least 0.55 em in radius; MathJax lacks this command and KaTeX has it.
- `\cancel`, `\bcancel`, `\xcancel`: strokes reaching 0.1 em past the list, which keeps 0.1 em of room on each side.
- `\phantom`, `\hphantom`, `\vphantom`: the room of the list, and nothing drawn.
- `\overset`, `\underset`, `\stackrel`: labels placed as an operator's limits. The class comes from the list under the label (a relation over `=`, ordinary over a letter), and `\stackrel` is always a relation, as in KaTeX.
- `\xrightarrow`, `\xleftarrow`, `\xleftrightarrow`, with an optional label below: relations, an arrow 0.3 em wider than its widest label on each side and at least 1.47 em. The heads are the font's `→` and `←` glyphs, with their shafts; a rule as thick as a glyph's shaft (measured from its outline) continues it. The rule starts where the glyph ends, because a formula's outlines are filled as one path and an overlap of opposite winding would be a hole. `\xRightarrow` and the other shapes are not typeset.
- `\overrightarrow`, `\overleftarrow`, `\overleftrightarrow`: the same arrow 0.1 em above the list, never narrower than its heads.
- `\mathord`, `\mathbin`, `\mathrel`, `\mathopen`, `\mathclose`, `\mathpunct`: the list as one atom of the class.
- `\big`, `\Big`, `\bigg`, `\Bigg`, with `l` (opening), `r` (closing), `m` (relation) or nothing (ordinary): a delimiter at least 1.2, 1.8, 2.4 or 3 em tall, KaTeX's heights. `\middle` draws its delimiter as tall as the `\left…\right` pair around it, found by typesetting a copy of the list first, since typesetting changes a list.

Regression tests: `AppProjectTextualPatchTests.testFramesAndCirclesStandAroundWhatTheyHold`, `testStrikeOutsCrossWhatTheyHold`, `testPhantomsKeepTheRoomOfWhatTheyHideAndDrawNothing`, `testOversetUndersetAndStackrelKeepTheClassOfWhatTheyStandOver`, `testExtensibleArrowsAreRelationsAsWideAsTheirLabels`, `testArrowsOverAListSpanIt`, `testClassCommandsSpaceTheirArgumentAsTheClass`, `testSizedDelimitersGrowInKaTeXSteps`, `testMiddleDelimiterIsAsTallAsItsPair`, `testInlineFormulasWithTheNewCommandsStayOneFormula`. They count ink through `Math` itself, so they cover the outlines `Math` draws.

## 13. `array`, table rules, row heights

`Sources/SwiftUIMath/Internal/Syntax/Parser.swift`, `Parser+GraphiteCommands.swift`, `AtomFactory.swift`, `Atoms/Table.swift`, `Internal/Display/Typesetter.swift`, `Typesetter+DecoratedList.swift`.

- `array` is typeset: cells in text style, columns 1 em apart (twice `\arraycolsep`) and aligned as the preamble says. `p{…}`, `m{…}` and `b{…}` columns are left-aligned, and `@{…}` and `!{…}` are skipped.
- `\hline` and a preamble's `|` are drawn, double rules too. `\hdashline` is drawn solid, and a preamble's dashed `:` is not drawn.
- A row break's length (`\\[2pt]`) adds that height above the next row. Upstream drew `[2pt]` as text in the cell.
- A row break at the end of a table, or one with only `\hline` after it, begins no row.
- `cases` takes any number of left-aligned columns, as in MathJax, and `gathered` is `gather`.
- `\substack` owns its row breaks. Inside an environment they ended the environment's row, and the formula could not be parsed.

Regression tests: `AppProjectTextualPatchTests.testArrayAlignsItsColumnsAsItsPreambleSays`, `testRowBreakLengthAddsHeightAndIsNotDrawn`, `testCasesGatheredAndSubstackInAnEnvironment`.

## 14. `\dbinom`, `\tbinom`, `\operatorname*`, `\hspace`

`Sources/SwiftUIMath/Internal/Syntax/Parser.swift`, `Parser+GraphiteCommands.swift`: `\dbinom` and `\tbinom` are binomials in display and script size. `\operatorname*{name}` is an upright operator with limits, as `\lim` is, with small spaces in its name kept (`arg\,max`); a name that is not plain letters is drawn upright, without limits. `\hspace` and `\hspace*` are spaces of their length, in TeX's units at a 10 pt font.

Regression test: `AppProjectTextualPatchTests.testBinomialStylesStarredOperatorNamesAndHorizontalSpaces`.

## 15. Spaces and style changes have no class

`Sources/SwiftUIMath/Internal/Syntax/AtomList.swift` (`finalized`): whether a binary operator is a sign looks past spaces and style changes to the last atom with a class, as TeX does. Upstream looked only at the atom before it, so the minus of `\rightarrow \quad -\frac{1}{2}` stayed a binary operator after a relation, which stopped Debug builds on an `assert` in `Typesetter.getInterElementSpace`, and the minus at the start of a matrix's cell, after the cell's style change, had a binary operator's spaces (`− 1`). Numbers still merge only when they are neighbours, so `1\,000` keeps its space.

Regression test: `AppProjectTextualPatchTests.testSpacesAndStyleChangesHaveNoClass`.

## 16. Bold symbols

`Sources/SwiftUIMath/Internal/Display/Typesetter.swift` (`preprocessMathList`), `Typesetter+DecoratedList.swift` (`boldOrdinarySymbol`): `\nabla`, `\partial`, `\epsilon`, `\vartheta`, `\phi`, `\varrho` and `\varpi` take their bold forms under `\bm` and `\mathbf`. Upstream's bold alphabets skipped them, as they are not letters to it, and the owner's vault has `\boldsymbol{\nabla}` 844 times. `\nabla` is upright, as in MathJax. Symbols with no bold form in Latin Modern, such as `\times` and `\ell`, stay regular, where MathJax draws them bold.

Regression test: `AppProjectTextualPatchTests.testBoldSymbolsHaveTheirBoldForms`.
