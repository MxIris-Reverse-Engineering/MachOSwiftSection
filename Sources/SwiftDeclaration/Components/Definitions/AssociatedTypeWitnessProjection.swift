/// A conformance extension's associated-type witness, frozen into pure value
/// data at index time.
///
/// The underlying `MachOSwiftSection.AssociatedType` records resolve their
/// names through Mach-O-bound accessors, so anything Mach-O-free downstream
/// (notably `SwiftDiffing`'s snapshot projection) cannot read them after
/// indexing. The indexer therefore resolves each record into this projection
/// while the Mach-O is still in hand.
public struct AssociatedTypeWitnessProjection: Sendable, Codable, Equatable {
    /// The associated-type requirement's name (e.g. `Element`).
    public let name: String
    /// The witness type, demangled and printed (e.g. `Swift.Int`).
    public let substitutedTypeText: String

    public init(name: String, substitutedTypeText: String) {
        self.name = name
        self.substitutedTypeText = substitutedTypeText
    }
}
