/**
 * File: BaseNewItemPlan.swift
 * ---------------------------
 * Layer: Core
 * Description: What New in a base view gives the note it makes: the folder and the properties its filters imply, read
 *              as Obsidian 1.15 reads them.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 26/11/2026
 */

import Foundation

/// A value New writes into the note it makes. Links are kept as the files they reach, so they are written later with
/// the vault's link format from the new note's own place.
public indirect enum BaseNewItemValue: Hashable, Sendable {
    /// Written as a property with no value: a column of the view, `file.hasProperty("p")`, `!p.isEmpty()`.
    case empty
    case text(String)
    case number(Double)
    case boolean(Bool)
    case date(BaseDate)
    /// A link to a vault file: `this`, a file, or a link that resolves.
    case note(VaultPath, display: String?)
    /// A link that reaches no file, written as it was.
    case unresolvedLink(String, display: String?)
    case list([BaseNewItemValue])

    /// The files the value links to, for naming them before the note is written.
    public var linkedPaths: [VaultPath] {
        switch self {
        case .note(let path, _): [path]
        case .list(let elements): elements.flatMap(\.linkedPaths)
        case .empty, .text, .number, .boolean, .date, .unresolvedLink: []
        }
    }
}

/// One property of the note New makes, in the order Obsidian adds them.
public struct BaseNewItemProperty: Hashable, Sendable {
    public let name: String
    public let value: BaseNewItemValue

    public init(name: String, value: BaseNewItemValue) {
        self.name = name
        self.value = value
    }
}

/// The folder and properties a view's filters imply for a new note.
public struct BaseNewItemPlan: Hashable, Sendable {
    /// The folder `file.inFolder("F")` or `file.folder == "F"` names, as written; nil when no filter names one.
    public var filterFolder: String?
    public var properties: [BaseNewItemProperty]

    public init(filterFolder: String? = nil, properties: [BaseNewItemProperty] = []) {
        self.filterFolder = filterFolder
        self.properties = properties
    }

    /// Every file the properties link to.
    public var linkedPaths: [VaultPath] { properties.flatMap(\.value.linkedPaths) }
}

/// Reads a view's filters as Obsidian 1.15's New button reads them (`plugins.bases`, the function that builds a new
/// item's frontmatter): every rule of the base's and the view's filters, inside `and`, `or` and `not`, except those
/// under an odd number of `not`.
///
/// - `p == value`, `p >= value` and `p <= value` set `p` to the value, evaluated with the new note as the row, so `this`
///   is the note the base is shown in. A later rule replaces an earlier one's value.
/// - `p.contains(x)`, `containsAll`, `startsWith` and `endsWith` set `p` to `x` (a one-item list for a list property),
///   `p.containsAny(a, b)` to `a`, and `!p.isEmpty()` adds `p` empty. `list(p)` counts as `p`.
/// - `file.hasTag("t")` adds `t` to `tags`, `file.tags.contains…` sets `tags`, `file.hasProperty("p")` adds `p` empty,
///   and `file.inFolder("F")` or `file.folder == "F"` names the folder.
/// - Each note property of the view's columns not set yet is added empty.
///
/// A rule whose value cannot be evaluated is left out, as Obsidian leaves it out. Values keep their type (Obsidian
/// writes numbers, booleans and dates as their text).
public enum BaseNewItemPlanner {
    /// - Parameters:
    ///   - evaluator: Evaluates with `this` as the note the base is shown in.
    ///   - newNote: The note about to be made, as the row values are evaluated for.
    ///   - isListProperty: Whether the vault takes the property as a list (declared or inferred), so `contains` gives a list.
    public static func plan(definition: BaseDefinition, viewIndex: Int, evaluator: BaseEvaluator, newNote: BaseFileRecord,
                            isListProperty: @escaping (String) -> Bool) -> BaseNewItemPlan {
        guard definition.views.indices.contains(viewIndex) else { return BaseNewItemPlan() }
        let view = definition.views[viewIndex]
        var builder = PlanBuilder(evaluator: evaluator, newNote: newNote, isListProperty: isListProperty)
        let filters = [definition.filters, view.filters].compactMap { filter in filter }
        for (sourceText, isNegated) in filters.flatMap({ filter in rules(of: filter, isNegated: false) }) where !isNegated {
            guard case .success(let expression) = evaluator.parsed(sourceText) else { continue }
            builder.apply(expression)
        }
        for property in view.order {
            guard case .note(let name) = property else { continue }
            builder.setIfAbsent(name, .empty)
        }
        return builder.plan
    }

    /// The filter's expressions with whether an odd number of `not` holds each.
    static func rules(of filter: BaseFilter, isNegated: Bool) -> [(String, Bool)] {
        switch filter {
        case .expression(let sourceText): [(sourceText, isNegated)]
        case .and(let children), .or(let children): children.flatMap { child in rules(of: child, isNegated: isNegated) }
        case .not(let children): children.flatMap { child in rules(of: child, isNegated: !isNegated) }
        }
    }

    /// What a rule's left side names: a note property, a file field or a formula.
    enum PropertyTarget: Equatable {
        case note(String)
        case file(String)
        case formula(String)
    }

    /// Obsidian reads `note.p`, `file.f`, `formula.f`, `note["p"]`, a bare `p`, `file` itself and `list(p)`. `this.p`
    /// names nothing a new note can take.
    static func target(of expression: BaseExpression) -> PropertyTarget? {
        switch expression {
        case .member(.identifier(let group), let name):
            return namedTarget(group: group, name: name) ?? (group == "this" ? nil : .note(group + "." + name))
        case .subscripted(.identifier(let group), .literal(let key)):
            guard let name = subscriptName(key) else { return nil }
            return namedTarget(group: group, name: name)
        case .identifier(let name):
            if name == "file" { return .file("file") }
            return ["this", "note", "formula", "true", "false", "null"].contains(name) ? nil : .note(name)
        case .functionCall(let name, let arguments):
            return name == "list" && arguments.count == 1 ? target(of: arguments[0]) : nil
        case .member, .subscripted, .literal, .methodCall, .unary, .binary, .listLiteral:
            return nil
        }
    }

    private static func namedTarget(group: String, name: String) -> PropertyTarget? {
        switch group {
        case "note": .note(name)
        case "file": .file(name)
        case "formula": .formula(name)
        default: nil
        }
    }

    private static func subscriptName(_ key: BaseValue) -> String? {
        if case .string(let text) = key { return text }
        if case .number(let number) = key { return BaseValue.formatted(number) }
        return nil
    }
}

/// The properties being gathered, in the order they are first set, as a JavaScript object keeps its keys.
private struct PlanBuilder {
    let evaluator: BaseEvaluator
    let newNote: BaseFileRecord
    let isListProperty: (String) -> Bool
    private(set) var plan = BaseNewItemPlan()

    init(evaluator: BaseEvaluator, newNote: BaseFileRecord, isListProperty: @escaping (String) -> Bool) {
        self.evaluator = evaluator
        self.newNote = newNote
        self.isListProperty = isListProperty
    }

    private static let comparisonOperators: Set<BaseBinaryOperator> = [.equal, .greaterOrEqual, .lessOrEqual]
    private static let settingMethods: Set<String> = ["startsWith", "endsWith", "contains", "containsAll"]

    mutating func apply(_ expression: BaseExpression) {
        switch expression {
        case .unary(.not, .methodCall(let subject, "isEmpty", _)):
            if case .note(let name)? = BaseNewItemPlanner.target(of: subject) { setIfAbsent(name, .empty) }
        case .binary(let comparison, let left, let right) where Self.comparisonOperators.contains(comparison):
            guard let target = BaseNewItemPlanner.target(of: left), let value = argumentValue([right]) else { return }
            switch target {
            case .note(let name): set(name, value)
            case .file("folder") where comparison == .equal:
                if case .text(let folder) = value { plan.filterFolder = folder }
            case .file, .formula: break
            }
        case .methodCall(let subject, let method, let arguments):
            guard let target = BaseNewItemPlanner.target(of: subject), let value = argumentValue(arguments) else { return }
            switch target {
            case .note(let name): applyNoteMethod(method, name: name, value: value)
            case .file(let field): applyFileMethod(method, field: field, value: value)
            case .formula: break
            }
        case .literal, .identifier, .member, .subscripted, .functionCall, .unary, .binary, .listLiteral:
            break
        }
    }

    private mutating func applyNoteMethod(_ method: String, name: String, value: BaseNewItemValue) {
        let isList = isListProperty(name)
        if Self.settingMethods.contains(method) {
            if isList, case .list = value { set(name, value) } else { set(name, isList ? .list([value]) : value) }
        } else if method == "containsAny" {
            let first = Self.firstElement(of: value)
            set(name, isList ? .list([first]) : first)
        }
    }

    private mutating func applyFileMethod(_ method: String, field: String, value: BaseNewItemValue) {
        switch (field, method) {
        case ("file", "hasTag"):
            guard case .text(let tag) = value else { return }
            let existing = property(named: "tags")
            switch existing {
            case nil: set("tags", .list([.text(tag)]))
            case .list(let tags)?: set("tags", .list(tags + [.text(tag)]))
            case .some: break
            }
        case ("file", "inFolder"):
            if case .text(let folder) = value { plan.filterFolder = folder }
        case ("file", "hasProperty"):
            if case .text(let name) = value { set(name, .empty) }
        case ("tags", "containsAny"):
            set("tags", .list([Self.firstElement(of: value)]))
        case ("tags", "contains"), ("tags", "containsAll"):
            if case .list = value { set("tags", value) } else { set("tags", .list([value])) }
        default:
            break
        }
    }

    private static func firstElement(of value: BaseNewItemValue) -> BaseNewItemValue {
        if case .list(let elements) = value { return elements.first ?? .empty }
        return value
    }

    private func property(named name: String) -> BaseNewItemValue? {
        plan.properties.first { property in property.name == name }?.value
    }

    mutating func set(_ name: String, _ value: BaseNewItemValue) {
        if let index = plan.properties.firstIndex(where: { property in property.name == name }) {
            plan.properties[index] = BaseNewItemProperty(name: name, value: value)
        } else {
            plan.properties.append(BaseNewItemProperty(name: name, value: value))
        }
    }

    mutating func setIfAbsent(_ name: String, _ value: BaseNewItemValue) {
        guard property(named: name) == nil else { return }
        plan.properties.append(BaseNewItemProperty(name: name, value: value))
    }

    /// The arguments' value, a list for several; nil when one cannot be evaluated. Each is evaluated with the new note as
    /// the row, then without a row, as Obsidian falls back to the base's own context.
    private func argumentValue(_ arguments: [BaseExpression]) -> BaseNewItemValue? {
        guard !arguments.isEmpty else { return nil }
        var values: [BaseNewItemValue] = []
        for argument in arguments {
            let evaluated: BaseValue
            if let withRow = try? evaluator.evaluate(argument, for: newNote) { // A rule Obsidian cannot evaluate is skipped.
                evaluated = withRow
            } else if let withoutRow = try? evaluator.evaluate(argument, for: nil) { // The same, without the new note.
                evaluated = withoutRow
            } else {
                return nil
            }
            values.append(newItemValue(evaluated))
        }
        return values.count == 1 ? values[0] : .list(values)
    }

    private func newItemValue(_ value: BaseValue) -> BaseNewItemValue {
        switch value {
        case .null: return .empty
        case .boolean(let isTrue): return .boolean(isTrue)
        case .number(let number): return .number(number)
        case .string(let text), .html(let text), .image(let text), .icon(let text): return .text(text)
        case .date(let date): return .date(date)
        case .file(let path): return .note(path, display: nil)
        case .link(let link):
            guard !link.isExternal, let path = evaluator.resolveLink(link.target, from: link.source) else {
                return .unresolvedLink(link.target, display: link.display)
            }
            return .note(path, display: link.display)
        case .list(let elements): return .list(elements.map(newItemValue))
        case .duration, .object, .regularExpression: return .text(value.displayText)
        }
    }
}
