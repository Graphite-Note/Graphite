import XCTest
@testable import MermaidDiagrams

/// A type's options under the front matter's `config:`, read from block YAML as Mermaid reads it with the JSON schema,
/// and those of `%%{init: …}%%` directives over them, as Pele reads them.
final class MermaidConfigurationOptionsTests: XCTestCase {
    private func options(_ source: String, section: String = "sankey") -> [String: MermaidConfigurationOptions.Value] {
        MermaidConfigurationOptions(section: section, in: Array(source.utf8)).values
    }

    func testScalarsAreReadAsBooleansNumbersAndText() {
        let read = options("---\nconfig:\n  sankey:\n    showValues: false\n    width: 900\n    nodePadding: 2.5e1\n    prefix: \"$\"\n"
                           + "    suffix: ' TWh'\n    nodeAlignment: left # a comment\n---\nsankey\na,b,1")
        XCTAssertEqual(read["showValues"], .boolean(false))
        XCTAssertEqual(read["width"], .number(900))
        XCTAssertEqual(read["nodePadding"], .number(25))
        XCTAssertEqual(read["prefix"], .text("$"))
        XCTAssertEqual(read["suffix"], .text(" TWh"))
        XCTAssertEqual(read["nodeAlignment"], .text("left"))
    }

    func testANestedMappingIsACollectionAndOtherSectionsAreLeft() {
        let source = "---\ntitle: Energy\nconfig:\n  theme: dark\n  sankey:\n    nodeColors:\n      Electricity grid: \"#4e79a7\"\n"
            + "    labelStyle: outlined\n  xyChart:\n    width: 300\n---\nsankey\na,b,1"
        let read = options(source)
        XCTAssertEqual(read, ["nodeColors": .collection, "labelStyle": .text("outlined")])
        XCTAssertEqual(options(source, section: "xyChart"), ["width": .number(300)])
    }

    func testTextWithoutFrontMatterOrConfigurationHasNoOptions() {
        XCTAssertTrue(options("sankey\na,b,1").isEmpty)
        XCTAssertTrue(options("---\ntitle: Only a title\n---\nsankey\na,b,1").isEmpty)
        XCTAssertTrue(options("---\nconfig:\n  sankey:\n    width: 900\n").isEmpty, "Front matter without its closing line is not read")
    }

    func testOnlyTheJSONSchemasWordsAndNumbersAreBooleansAndNumbers() {
        let read = options("---\nconfig:\n  sankey:\n    a: True\n    b: 0x1F\n    c: .5\n    d: \"12\"\n    e: [1, 2]\n---\n")
        XCTAssertEqual(read["a"], .text("True"))
        XCTAssertEqual(read["b"], .text("0x1F"))
        XCTAssertEqual(read["c"], .number(0.5))
        XCTAssertEqual(read["d"], .text("12"))
        XCTAssertEqual(read["e"], .collection)
    }

    // MARK: Directives

    func testADirectivesOptionsAreAppliedOverTheFrontMattersWhereverItStands() {
        let frontMatter = "---\nconfig:\n  pie:\n    textPosition: 0.3\n    donutHole: 0.2\n---\n"
        XCTAssertEqual(options(frontMatter + "%%{init: {'pie': {'donutHole': 0.5, 'legendPosition': 'top'}}}%%\npie\n\"a\" : 1", section: "pie"),
                       ["textPosition": .number(0.3), "donutHole": .number(0.5), "legendPosition": .text("top")],
                       "The directive's apostrophes are quotation marks for its JSON, and its option is over the front matter's.")
        XCTAssertEqual(options("pie\n\"a\" : 1 %%{initialize: {\"pie\": {\"donutHole\": 0.4}}}%% \n", section: "pie"), ["donutHole": .number(0.4)],
                       "Within a line, after the keyword, and named initialize.")
        XCTAssertEqual(options("%%{\n  init: {\n    \"sankey\": {\"showValues\": false}\n  }\n}%%\nsankey\na,b,1"), ["showValues": .boolean(false)],
                       "Over several lines.")
    }

    func testDirectivesMergeInTheirOrderAndOneThatCannotBeReadIsLeftOut() {
        let source = "%%{init: {'sankey': {'width': 300, 'prefix': '$'}}}%%\n%%{init: {'sankey': {'width': 500,}}}%%\n"
            + "%%{init: {'sankey': {'width': 400, 'nodeColors': {'a': 'red'}, 'suffix': null}}}%%\nsankey\na,b,1"
        XCTAssertEqual(options(source), ["width": .number(400), "prefix": .text("$"), "nodeColors": .collection],
                       "The second directive's JSON is not read; null sets nothing.")
        XCTAssertTrue(options("%%{wrap}%%\n%%{config: {'sankey': {'width': 1}}}%%\n%%{init: dark}%%\n%%{init: {'theme': 'dark'}}%%\nsankey\na,b,1").isEmpty,
                      "Other directives, a single word and other sections set nothing.")
        XCTAssertTrue(options("---\ntitle: \"%%{init: {'sankey': {'width': 1}}}%%\"\n---\nsankey\na,b,1").isEmpty, "Within the front matter it is no directive.")
    }

    func testADirectiveThatGivesTheTypeSomethingOtherThanAnObjectLeavesItNoOption() {
        XCTAssertTrue(options("---\nconfig:\n  sankey:\n    width: 900\n---\n%%{init: {'sankey': 5}}%%\nsankey\na,b,1").isEmpty)
    }

    func testJSONValuesAreBooleansNumbersTextAndCollections() {
        let read = options("%%{init: {\"sankey\": {\"a\": true, \"b\": 1, \"c\": 2.5e1, \"d\": \"12\", \"e\": [1], \"f\": {}, \"g\": 0}}}%%\nsankey")
        XCTAssertEqual(read, ["a": .boolean(true), "b": .number(1), "c": .number(25), "d": .text("12"), "e": .collection, "f": .collection, "g": .number(0)])
    }
}
