/**
 * File: BaseViewPluginOptionRow.swift
 * -----------------------------------
 * Layer: UI
 * Description: One option of a view a community plugin draws, as a row of the view editor.
 *
 * Authors: Bahey Shalash
 * Version: 0.1
 * Date: 01/11/2026
 */

import SwiftUI
import GraphiteCore

/// One option of a plugin's view. An option never set shows the plugin's default, and stays
/// out of the file until it is changed.
struct BaseViewPluginOptionRow: View {
    let option: CommunityPluginBasesViewRegistration.Option
    @Binding var value: BaseViewOptionValue?

    private var shownValue: BaseViewOptionValue? { value ?? option.defaultValue }

    private var text: String {
        switch shownValue {
        case .text(let text): text
        case .number(let number): BaseValue.formatted(number)
        case .boolean(let isOn): isOn ? "true" : "false"
        case nil: ""
        }
    }

    private var number: Double {
        if case .number(let number) = shownValue { return number }
        return option.minimum ?? 0
    }

    var body: some View {
        switch option.kind {
        case .text:
            TextField(option.displayName, text: Binding(get: { text }, set: { newText in value = newText.isEmpty ? nil : .text(newText) }))
        case .toggle:
            Toggle(option.displayName, isOn: Binding(get: { if case .boolean(true) = shownValue { return true } else { return false } },
                set: { isOn in value = .boolean(isOn) }))
        case .dropdown:
            Picker(option.displayName, selection: Binding(get: { text }, set: { choice in value = .text(choice) })) {
                ForEach(option.choices, id: \.value) { choice in Text(choice.title).tag(choice.value) }
            }
        case .slider:
            Stepper(value: Binding(get: { number }, set: { newNumber in value = .number(newNumber) }),
                in: (option.minimum ?? 0)...(max(option.minimum ?? 0, option.maximum ?? 100)), step: option.step ?? 1) {
                Text("\(option.displayName): \(BaseValue.formatted(number))")
            }
        case .other:
            LabeledContent(option.displayName) { Text("Edit this in the base file.").foregroundStyle(.secondary) }
        }
    }
}
