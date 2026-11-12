/// Why a state diagram was not laid out.
public enum StateDiagramLayoutError: Error, Equatable, Sendable {
    /// The diagram's composite states (`state Id { … }`) cannot be laid out as boxes: a transition joins a composite
    /// state to itself or to a state inside it, a note is written beside a composite state, a composite is inside itself
    /// through the states it holds, or two transitions must leave one rank of a box straight across its flow by one side.
    /// Drawn without its boxes, the diagram would look complete and be wrong.
    case compositeStatesNotLaidOut
    /// The states and the points transitions pass through would be more than the limit.
    case tooManyLayoutPoints(limit: Int)
}
