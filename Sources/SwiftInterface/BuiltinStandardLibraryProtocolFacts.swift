/// Frozen facts for standard-library protocols, keyed by demangled qualified
/// name (evolution proposal 0011). This is the only source of
/// primary-associated-type names and their declaration order — runtime
/// metadata carries no primary marker (SE-0346) — and the offline fallback
/// for external protocols a `MachOFile` can identify only by bind symbol.
///
/// Primary lists verified against `swift-6.3.2-RELEASE` stdlib sources
/// (`stdlib/public/core`, `stdlib/public/Concurrency`); Concurrency protocols
/// demangle under module `Swift` (`$sSciMp` → `Swift.AsyncSequence`). A
/// missing entry only means the chain falls through to a descriptor or to the
/// no-attachment degradation — never a wrong attachment.
enum BuiltinStandardLibraryProtocolFacts {
    static let factsByQualifiedName: [String: ProtocolFacts] = {
        var factsTable: [String: ProtocolFacts] = [:]

        func register(
            _ qualifiedName: String,
            associatedTypes declaredAssociatedTypeNames: [String] = [],
            refines refinedQualifiedNames: [String] = [],
            primary primaryAssociatedTypeNames: [String] = []
        ) {
            factsTable[qualifiedName] = ProtocolFacts(
                qualifiedName: qualifiedName,
                declaredAssociatedTypeNames: declaredAssociatedTypeNames,
                refinedProtocols: refinedQualifiedNames.map { ProtocolReference(qualifiedName: $0, descriptor: nil) },
                primaryAssociatedTypeNames: primaryAssociatedTypeNames
            )
        }

        // Protocols with primary associated types.
        register("Swift.Sequence", associatedTypes: ["Element", "Iterator"], primary: ["Element"])
        register("Swift.Collection", associatedTypes: ["Element", "Index", "Iterator", "SubSequence", "Indices"], refines: ["Swift.Sequence"], primary: ["Element"])
        register("Swift.BidirectionalCollection", refines: ["Swift.Collection"], primary: ["Element"])
        register("Swift.RandomAccessCollection", refines: ["Swift.BidirectionalCollection"], primary: ["Element"])
        register("Swift.MutableCollection", refines: ["Swift.Collection"], primary: ["Element"])
        register("Swift.RangeReplaceableCollection", refines: ["Swift.Collection"], primary: ["Element"])
        register("Swift.IteratorProtocol", associatedTypes: ["Element"], primary: ["Element"])
        register("Swift.RawRepresentable", associatedTypes: ["RawValue"], primary: ["RawValue"])
        register("Swift.Identifiable", associatedTypes: ["ID"], primary: ["ID"])
        register("Swift.Strideable", associatedTypes: ["Stride"], refines: ["Swift.Comparable"], primary: ["Stride"])
        register("Swift.RangeExpression", associatedTypes: ["Bound"], primary: ["Bound"])
        register("Swift.SetAlgebra", associatedTypes: ["Element", "ArrayLiteralElement"], refines: ["Swift.Equatable", "Swift.ExpressibleByArrayLiteral"], primary: ["Element"])
        register("Swift.SIMD", associatedTypes: ["Scalar", "MaskStorage"], refines: ["Swift.SIMDStorage", "Swift.Hashable", "Swift.CustomStringConvertible", "Swift.ExpressibleByArrayLiteral", "Swift.Encodable", "Swift.Decodable"], primary: ["Scalar"])
        register("Swift.InstantProtocol", associatedTypes: ["Duration"], refines: ["Swift.Comparable", "Swift.Hashable", "Swift.Sendable"], primary: ["Duration"])
        register("Swift.AsyncSequence", associatedTypes: ["AsyncIterator", "Element", "Failure"], primary: ["Element", "Failure"])
        register("Swift.AsyncIteratorProtocol", associatedTypes: ["Element", "Failure"], primary: ["Element", "Failure"])
        register("Swift.Clock", associatedTypes: ["Duration", "Instant"], refines: ["Swift.Sendable"], primary: ["Duration"])

        // Protocols without associated types — a registered empty entry is
        // what lets attribution say "never attach" instead of degrading.
        register("Swift.Equatable")
        register("Swift.Hashable", refines: ["Swift.Equatable"])
        register("Swift.Comparable", refines: ["Swift.Equatable"])
        register("Swift.Error")
        register("Swift.Sendable")
        register("Swift.CustomStringConvertible")
        register("Swift.CustomDebugStringConvertible")
        register("Swift.LosslessStringConvertible", refines: ["Swift.CustomStringConvertible"])
        register("Swift.Encodable")
        register("Swift.Decodable")
        register("Swift.CustomReflectable")
        register("Swift.CaseIterable", associatedTypes: ["AllCases"])
        register("Swift.ExpressibleByArrayLiteral", associatedTypes: ["ArrayLiteralElement"])
        register("Swift.SIMDStorage", associatedTypes: ["Scalar"])

        return factsTable
    }()
}
