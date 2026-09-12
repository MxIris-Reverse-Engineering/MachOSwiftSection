import SwiftDeclarationRendering

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
    /// The witness type, demangled with its opaque types expanded, and printed
    /// (e.g. `Swift.Int`).
    ///
    /// When the witness's underlying type is decided by an
    /// availability-conditional accessor thunk (evolution proposal
    /// `offline-opaque-accessor-thunk-resolution`), this is the branch the
    /// current platform takes; the other branches are in
    /// ``conditionalCandidates``.
    public let substitutedTypeText: String
    /// Every answer an availability-conditional accessor thunk inside the
    /// witness can give, one entry per branch; empty when the witness carries
    /// no such thunk or its shape could not be read.
    ///
    /// Filled by the offline reader only: in-process the runtime executes the
    /// thunk and answers for this OS alone, so there is nothing to list.
    public let conditionalCandidates: [ConditionalWitnessCandidate]

    public init(name: String, substitutedTypeText: String, conditionalCandidates: [ConditionalWitnessCandidate] = []) {
        self.name = name
        self.substitutedTypeText = substitutedTypeText
        self.conditionalCandidates = conditionalCandidates
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case substitutedTypeText
        case conditionalCandidates
    }

    /// Tolerates the key's absence so a projection persisted before
    /// `conditionalCandidates` existed still decodes.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        substitutedTypeText = try container.decode(String.self, forKey: .substitutedTypeText)
        conditionalCandidates = try container.decodeIfPresent([ConditionalWitnessCandidate].self, forKey: .conditionalCandidates) ?? []
    }
}

/// One answer an availability-conditional accessor thunk can give for an
/// associated-type witness.
///
/// A witness whose underlying type is an SE-0360 `if #available` opaque
/// result has one of these per branch. Both texts are carried on purpose: the
/// candidate type alone says which part of the witness changes, while the
/// whole witness with that branch substituted is what a host shows when asked
/// "what does this read as on that OS" — the thunk can sit anywhere in the
/// tree (`SwiftUI.FeedbackGenerator.Body` carries its inside a
/// `ModifiedContent<…>` chain), and a host should not have to know where.
public struct ConditionalWitnessCandidate: Sendable, Codable, Equatable {
    /// The platform version the branch is gated on, or `nil` when the thunk
    /// has no version check and this is its only answer.
    public let availability: PlatformAvailabilityCondition?
    /// The type the thunk yields on this branch, printed.
    public let candidateTypeText: String
    /// The whole witness with this branch substituted, printed.
    public let substitutedTypeText: String

    public init(availability: PlatformAvailabilityCondition?, candidateTypeText: String, substitutedTypeText: String) {
        self.availability = availability
        self.candidateTypeText = candidateTypeText
        self.substitutedTypeText = substitutedTypeText
    }
}
