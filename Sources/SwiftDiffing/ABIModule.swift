import SwiftDeclaration

/// The fully-indexed, Mach-O-free snapshot of a binary's Swift declarations
/// that `ABIDiffer` consumes.
///
/// Per the model's contract, a `Definition` no longer depends on its Mach-O
/// once indexed — so the caller indexes both binaries (via `SwiftIndexing`),
/// ensures every definition is fully indexed, and hands the resulting
/// collections here. The differ itself touches no Mach-O and is synchronous.
///
/// Not `Sendable`: it holds the reference-type `*Definition` model objects. The
/// differ is synchronous and single-threaded, so this is not a constraint.
///
/// `protocols` and `extensions` are accepted for forward-compatibility but are
/// **not yet diffed** — `ABIDiffer` currently reports `types` only. Populating
/// them is harmless (the data is ignored until the P2 axes land), but be aware
/// the result will not reflect protocol/extension changes yet.
public struct ABIModule {
    public let types: [TypeDefinition]
    /// TODO(P2): not yet consumed by `ABIDiffer.diff`.
    public let protocols: [ProtocolDefinition]
    /// TODO(P2): not yet consumed by `ABIDiffer.diff`.
    public let extensions: [ExtensionDefinition]

    public init(
        types: [TypeDefinition],
        protocols: [ProtocolDefinition] = [],
        extensions: [ExtensionDefinition] = []
    ) {
        self.types = types
        self.protocols = protocols
        self.extensions = extensions
    }
}
