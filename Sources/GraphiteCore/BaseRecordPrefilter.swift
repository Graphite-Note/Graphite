/**
 * File: BaseRecordPrefilter.swift
 * -------------------------------
 * Layer: Core
 * Description: The part of a base's filters the index can answer, as a tree of conditions the index turns into SQL.
 *
 * Authors: Bahey Shalash
 * Version: 0.2
 * Date: 05/11/2026
 */

import Foundation

/// What a link requirement points at.
public enum BaseLinkDestination: Hashable, Sendable {
    case path(VaultPath)
    /// A written link target, resolved by the index.
    case target(String)
}

/// A condition every matching file must satisfy, cheap enough for the index to check
/// with its B-tree tables. Each case is satisfied when any of its options holds.
public enum BasePrefilterRequirement: Hashable, Sendable {
    case inAnyFolder([String])
    /// Tags without `#`; nested tags (`book/fiction` for `book`) also match.
    case hasAnyTag([String])
    case hasAnyExtension([String])
    case hasAnyProperty([String])
    case linksTo(BaseLinkDestination)
    /// `file.folder == "Folder"`: the file sits directly in the folder; `/` is the vault root.
    case inExactFolder(String)
    /// `file.name == "Name.md"`.
    case hasAnyFileName([String])
    /// `file.basename == "Name"`.
    case hasAnyBasename([String])
}

/// The part of a base's filters the index can answer, kept as the filters combine them.
///
/// Every condition stands for a filter, and the index reads it two ways: as a superset
/// (every file for which the filter is true) and, for an exact condition, as a subset
/// (only files for which the filter is true). `noneOf` needs the subset of what it
/// negates, so only exact conditions narrow a `not`. A condition is exact when every
/// requirement in it is, and an exact filter never fails to evaluate.
public indirect enum BasePrefilterCondition: Hashable, Sendable {
    /// A filter the index cannot answer: any file may satisfy it, and it may fail.
    case anyFile
    /// A requirement every file satisfying the filter meets. `isExact` when the files
    /// meeting it are exactly those for which the filter is true.
    case requirement(BasePrefilterRequirement, isExact: Bool)
    case propertyText(BasePropertyTextRequirement)
    case allOf([BasePrefilterCondition])
    case anyOf([BasePrefilterCondition])
    case noneOf([BasePrefilterCondition])
}

/// A note property that can equal a text only when its stored value contains that
/// text, from a filter such as `status == "reading"`. The text holds only ASCII
/// letters, digits and spaces, and does not read as a number.
///
/// A file satisfies it when it has a property named `key` (any capitalization) whose
/// indexed value contains `text` ignoring ASCII case, or contains `%` or any non-ASCII
/// character: the evaluator decodes percent-encoded link targets and compares text
/// with Unicode normalization, which can turn those into the text.
public struct BasePropertyTextRequirement: Hashable, Sendable {
    public let key: String
    public let text: String
    public init(key: String, text: String) {
        self.key = key
        self.text = text
    }
}

/// Conditions extracted from a base's filters so the index loads only files that can
/// possibly match. It is always a superset of the true result: anything the
/// extraction does not fully understand is left to the evaluator, which checks every
/// loaded file.
public struct BaseRecordPrefilter: Hashable, Sendable {
    public var condition: BasePrefilterCondition

    public init(condition: BasePrefilterCondition) {
        self.condition = condition
    }

    /// Every one of the requirements must hold, and every one of the property texts.
    public init(requirements: [BasePrefilterRequirement] = [], propertyTextRequirements: [BasePropertyTextRequirement] = []) {
        condition = .allOf(requirements.map { requirement in .requirement(requirement, isExact: false) }
                           + propertyTextRequirements.map(BasePrefilterCondition.propertyText))
    }

    /// The requirements every matching file meets, outside any `or` or `not`.
    public var requirements: [BasePrefilterRequirement] {
        var found: [BasePrefilterRequirement] = []
        for condition in Self.conjuncts(of: condition) {
            if case .requirement(let requirement, _) = condition, !found.contains(requirement) { found.append(requirement) }
        }
        return found
    }

    /// The property texts every matching file contains, outside any `or` or `not`.
    public var propertyTextRequirements: [BasePropertyTextRequirement] {
        var found: [BasePropertyTextRequirement] = []
        for condition in Self.conjuncts(of: condition) {
            if case .propertyText(let requirement) = condition, !found.contains(requirement) { found.append(requirement) }
        }
        return found
    }

    private static func conjuncts(of condition: BasePrefilterCondition) -> [BasePrefilterCondition] {
        if case .allOf(let children) = condition { return children.flatMap(conjuncts) }
        return [condition]
    }

    /// The conditions implied by `filters`, all of which must hold: `and`, `or` and `not`
    /// groups, and `&&`, `||` and `!` inside an expression, keep their shape.
    public static func extract(from filters: [BaseFilter], definition: BaseDefinition, environment: BaseEvaluationEnvironment, thisRecord: BaseFileRecord?, provider: (any BaseRecordProvider)? = nil) -> BaseRecordPrefilter {
        let evaluator = BaseEvaluator(formulas: definition.formulas, environment: environment, thisRecord: thisRecord, provider: provider)
        func condition(for filter: BaseFilter) -> BasePrefilterCondition {
            switch filter {
            case .expression(let sourceText):
                guard case .success(let expression) = evaluator.parsed(sourceText) else { return .anyFile }
                return condition(for: expression)
            case .and(let children):
                return combined(.allOf(children.map(condition)))
            case .or(let children):
                // An empty `or` holds for every file.
                return children.isEmpty ? .anyFile : combined(.anyOf(children.map(condition)))
            case .not(let children):
                return .noneOf(children.map(condition))
            }
        }
        func condition(for expression: BaseExpression) -> BasePrefilterCondition {
            if case .binary(.and, let leftExpression, let rightExpression) = expression {
                return combined(.allOf([condition(for: leftExpression), condition(for: rightExpression)]))
            }
            if case .binary(.or, let leftExpression, let rightExpression) = expression {
                return combined(.anyOf([condition(for: leftExpression), condition(for: rightExpression)]))
            }
            if case .unary(.not, let operand) = expression { return .noneOf([condition(for: operand)]) }
            var parts: [BasePrefilterCondition] = []
            if let (requirement, isExact) = requirement(for: expression, evaluator: evaluator) { parts.append(.requirement(requirement, isExact: isExact)) }
            if let requirement = propertyTextRequirement(for: expression, evaluator: evaluator) { parts.append(.propertyText(requirement)) }
            if parts.isEmpty { return .anyFile }
            return parts.count == 1 ? parts[0] : .allOf(parts)
        }
        return BaseRecordPrefilter(condition: combined(.allOf(filters.map(condition))))
    }

    /// Nested groups of the same kind as one, and a group of one as its child. Neither
    /// changes which files hold, nor whether the group is exact.
    private static func combined(_ condition: BasePrefilterCondition) -> BasePrefilterCondition {
        switch condition {
        case .allOf(let children):
            let flattened = children.flatMap { child -> [BasePrefilterCondition] in
                if case .allOf(let grandchildren) = child { return grandchildren }
                return [child]
            }
            return flattened.count == 1 ? flattened[0] : .allOf(flattened)
        case .anyOf(let children):
            // One child the index cannot answer lets any file through the whole group.
            if children.contains(.anyFile) { return .anyFile }
            let flattened = children.flatMap { child -> [BasePrefilterCondition] in
                if case .anyOf(let grandchildren) = child { return grandchildren }
                return [child]
            }
            return flattened.count == 1 ? flattened[0] : .anyOf(flattened)
        case .anyFile, .requirement, .propertyText, .noneOf:
            return condition
        }
    }

    private static let reservedNames: Set<String> = ["file", "note", "formula", "this"]

    /// The note property an expression reads directly, if any.
    private static func notePropertyName(_ expression: BaseExpression) -> String? {
        switch expression {
        case .identifier(let name) where !reservedNames.contains(name): return name
        case .member(.identifier("note"), let name): return name
        case .subscripted(.identifier("note"), .literal(.string(let name))): return name
        default: return nil
        }
    }

    /// Evaluates an argument that does not depend on the row (literals, `this`, …).
    private static func constantValue(_ expression: BaseExpression, evaluator: BaseEvaluator) -> BaseValue? {
        guard !expression.dependsOnCurrentRow, let value = try? evaluator.evaluate(expression, for: nil), !value.isNull else { return nil }
        return value
    }

    /// Whether every argument is a non-empty text, as `file.hasTag` and `file.inFolder`
    /// read them exactly. Other values are read through their display text, which the
    /// index's requirement covers but not exactly.
    private static func areAllNonEmptyTexts(_ values: [BaseValue]) -> Bool {
        values.allSatisfy { value in
            if case .string(let text) = value { return !text.isEmpty && text != "#" }
            return false
        }
    }

    /// The requirement of `file.inFolder`, `file.hasTag`, `file.hasProperty` or `file.hasLink`
    /// with arguments that do not depend on the row, and whether it is exact.
    private static func fileFunctionRequirement(_ name: String, arguments: [BaseExpression], evaluator: BaseEvaluator) -> (BasePrefilterRequirement, Bool)? {
        let constants = arguments.map { argument in constantValue(argument, evaluator: evaluator) }
        guard !constants.isEmpty, constants.allSatisfy({ constant in constant != nil }) else { return nil }
        let values = constants.compactMap { constant in constant }
        switch name {
        case "inFolder":
            let folder = BaseEvaluator.normalizedFolderPath(values[0].displayText)
            return folder.isEmpty ? nil : (.inAnyFolder([folder]), values.count == 1 && areAllNonEmptyTexts(values))
        case "hasTag":
            let tags = values.map { value in value.displayText.hasPrefix("#") ? String(value.displayText.dropFirst()) : value.displayText }
            return (.hasAnyTag(tags), areAllNonEmptyTexts(values))
        case "hasProperty":
            return (.hasAnyProperty([values[0].displayText]), false)
        case "hasLink":
            // `file("Name")` resolves a written name from each row's own folder, while the
            // constant above resolved it from the vault root. The root's file is only one
            // of the files the name can mean, so the index keeps links to any of them.
            if case .functionCall("file", let fileArguments) = arguments[0], fileArguments.count == 1,
               let writtenName = constantValue(fileArguments[0], evaluator: evaluator) {
                switch writtenName {
                case .string(let text): return (.linksTo(.target(BaseLink.parse(text)?.pathPart ?? text)), false)
                case .link(let link) where !link.isExternal: return (.linksTo(.target(link.pathPart)), false)
                default: return nil
                }
            }
            switch values[0] {
            case .file(let path): return (.linksTo(.path(path)), false)
            case .link(let link) where !link.isExternal: return (.linksTo(.target(link.pathPart)), false)
            case .string(let text): return (.linksTo(.target(BaseLink.parse(text)?.pathPart ?? text)), false)
            default: return nil
            }
        default:
            return nil
        }
    }

    /// The requirement an expression implies, and whether it is exact (see
    /// `BasePrefilterCondition`).
    private static func requirement(for expression: BaseExpression, evaluator: BaseEvaluator) -> (BasePrefilterRequirement, Bool)? {
        switch expression {
        case .methodCall(.identifier("file"), let name, let arguments):
            return fileFunctionRequirement(name, arguments: arguments, evaluator: evaluator)
        case .methodCall(.member(.identifier("file"), "tags"), let name, let arguments) where ["contains", "containsAny"].contains(name):
            // `file.tags` lists each tag with `#`, compared exactly; the index's tag
            // requirement, which ignores case and takes nested tags too, covers it.
            var tags: [String] = []
            for argument in arguments {
                guard case .string(let text)? = constantValue(argument, evaluator: evaluator) else { return nil }
                tags.append(text.hasPrefix("#") ? String(text.dropFirst()) : text)
            }
            return tags.isEmpty || tags.contains(where: \.isEmpty) ? nil : (.hasAnyTag(tags), false)
        case .binary(let binaryOperator, let leftExpression, let rightExpression):
            guard [.equal, .less, .lessOrEqual, .greater, .greaterOrEqual].contains(binaryOperator) else { return nil }
            for (propertyExpression, otherExpression) in [(leftExpression, rightExpression), (rightExpression, leftExpression)] {
                if binaryOperator == .equal, case .member(.identifier("file"), let fieldName) = propertyExpression,
                   ["ext", "folder", "name", "basename"].contains(fieldName) {
                    guard case .string(let text)? = constantValue(otherExpression, evaluator: evaluator), !text.isEmpty else { return nil }
                    switch fieldName {
                    // Every file without an extension has the empty one, which no
                    // `*.extension` path pattern selects.
                    case "ext": return (.hasAnyExtension([text]), false)
                    // A folder never ends with a slash; the root reads as `/`.
                    case "folder": return text != "/" && text.hasSuffix("/") ? nil : (.inExactFolder(text), false)
                    case "name": return (.hasAnyFileName([text]), false)
                    default: return (.hasAnyBasename([text]), false)
                    }
                }
                // A missing property is empty, and empty never equals or orders against a
                // non-empty constant, so the property must exist.
                if let propertyName = notePropertyName(propertyExpression), let constant = constantValue(otherExpression, evaluator: evaluator), !constant.isNull {
                    return (.hasAnyProperty([propertyName]), false)
                }
            }
            return nil
        case .methodCall(let receiver, let name, _):
            // These return false for an empty receiver, so the property must exist.
            guard ["contains", "containsAll", "containsAny", "startsWith", "endsWith"].contains(name), let propertyName = notePropertyName(receiver) else { return nil }
            return (.hasAnyProperty([propertyName]), false)
        default:
            return nil
        }
    }

    /// Letters, digits and spaces are stored unescaped in the index's JSON and compared
    /// by exact text or, against a link, by its lowercased target with surrounding
    /// spaces trimmed. Text that reads as a number is excluded, because `==` compares it
    /// with a number by value (`"1e1"` equals `10`).
    private static let propertyTextCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 ")

    private static func propertyTextRequirement(for expression: BaseExpression, evaluator: BaseEvaluator) -> BasePropertyTextRequirement? {
        guard case .binary(.equal, let leftExpression, let rightExpression) = expression else { return nil }
        for (propertyExpression, otherExpression) in [(leftExpression, rightExpression), (rightExpression, leftExpression)] {
            guard let propertyName = notePropertyName(propertyExpression), case .string(let text)? = constantValue(otherExpression, evaluator: evaluator) else { continue }
            let trimmedText = text.trimmingCharacters(in: .whitespaces)
            guard !trimmedText.isEmpty, text.unicodeScalars.allSatisfy(propertyTextCharacters.contains), Double(trimmedText) == nil else { return nil }
            return BasePropertyTextRequirement(key: propertyName, text: trimmedText)
        }
        return nil
    }
}
