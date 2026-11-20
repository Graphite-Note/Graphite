/**
 * File: ReadingSequenceWording.swift
 * ----------------------------------
 * Layer: UI
 * Description: What is wrong on a line of a sequence diagram, in words.
 *
 * Authors: Félix Chevalier, Bahey Shalash
 * Version: 0.3
 * Date: 20/11/2026
 */

import MermaidDiagrams

extension SequenceSyntaxProblem {
    /// What is wrong on the line, as the end of the sentence `MermaidDiagramPreparationFailure.explanation` starts.
    var explanation: String {
        switch self {
        case .expectedParticipant: "a participant’s name is missing"
        case .expectedArrow: "a message has no arrow (such as ->> or -->>)"
        case .expectedText: "a message or a note has no “:” before its text"
        case .expectedNotePlacement: "a note does not say “left of”, “right of” or “over”"
        case .endWithoutBlock: "“end” closes no block"
        case .sectionOutsideItsBlock(let keyword): "“\(keyword)” is outside the block it belongs to"
        case .unclosedBlock(let keyword): "the “\(keyword)” block has no “end”"
        case .inactiveParticipantDeactivated(let identifier): "“\(identifier)” is deactivated while it is not active"
        case .createdParticipantAlreadyNamed(let identifier): "“\(identifier)” is created after it was already named"
        case .createdParticipantWithoutCreatingMessage(let identifier): "“\(identifier)” is created with no message to it on the next line"
        case .destroyedParticipantWithoutDestroyingMessage(let identifier): "“\(identifier)” is destroyed with no message to or from it on the next line"
        case .participantInTwoBoxes(let identifier): "“\(identifier)” is in two boxes"
        case .invalidParticipantAttributes(let identifier): "the attributes of “\(identifier)” cannot be read"
        }
    }
}
