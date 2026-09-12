#if THUNK_ANALYSIS

import Foundation

/// A type a thunk computes, written as what the instructions *say* rather
/// than as an address: which argument it started from, which accessor it
/// called with which arguments.
///
/// This is what lets a type-construction thunk be read without executing it.
/// Every call such a thunk makes is one of a handful of runtime entry points
/// whose meaning is type-level — "the metadata of `Foo` for these arguments",
/// "the witness table for this conformance" — so the result can be written
/// down as a term over those calls and turned into a demangling tree
/// afterwards, with the thunk's own generic arguments still symbolic.
public indirect enum ThunkTypeExpression: Sendable, Hashable {
    /// The `index`-th word of the argument buffer the thunk was handed: its
    /// owner's `index`-th key generic argument (parameters first, witness
    /// tables after, the order `enumerateGenericSignatureRequirements` emits
    /// and the runtime's generic-argument layout stores).
    case argument(index: Int)

    /// Metadata materialized as a constant address — an `adrp` / `add` onto a
    /// `…VN` record.
    case constantMetadata(address: UInt64)

    /// The result of calling the metadata accessor at `accessorAddress` with
    /// these type arguments; witness-table arguments are already dropped, in
    /// the accessor's own argument order.
    case bound(accessorAddress: UInt64, typeArguments: [ThunkTypeExpression])

    /// A type instantiated from a mangled name the thunk points at
    /// (`__swift_instantiateConcreteTypeFromMangledNameV2`). The addresses are
    /// what the thunk passed in `x0` and `x1`; the reader finds the mangled
    /// name's relative pointer among them.
    case instantiatedFromMangledName(argumentAddresses: [UInt64])
}

/// What one slot of a metadata accessor's key-argument list carries.
public enum ThunkArgumentSlot: Sendable, Hashable {
    /// Type metadata — the slot that names something.
    case type
    /// A protocol witness table — needed by the runtime, not by a name.
    case witnessTable
    /// A shape class or a value argument; not named by this analysis.
    case other
}

/// What the function a thunk calls is, as far as the analysis needs to know.
public enum ThunkCallee: Sendable, Hashable {
    /// A nominal type's metadata accessor (`$s…Ma`): `(request, key arguments…)`,
    /// the arguments in `x1`–`x3` when there are at most three and otherwise
    /// in a buffer `x1` points at.
    case metadataAccessor(address: UInt64, argumentSlots: [ThunkArgumentSlot])
    /// `swift_getWitnessTable` — yields a witness table.
    case witnessTableLookup
    /// `__swift_instantiateConcreteTypeFromMangledNameV2` — yields the type a
    /// mangled name spells.
    case mangledNameInstantiation
    /// `swift_checkMetadataState(request, metadata)` — returns the metadata
    /// it was handed (completed), so for naming it is the identity on its
    /// second argument.
    case metadataStateCheck
    /// `__isPlatformVersionAtLeast` — the availability check; the branch
    /// structure around it is the shape recognizer's business.
    case availabilityCheck
    /// Anything else. A branch whose result depends on it is not read.
    case unknown
}

/// What the evaluator asks its surroundings for: what a call target is, and
/// what a pointer-sized word in the binary holds.
///
/// A protocol so the evaluator runs from synthesized instruction sequences
/// with a tabled environment, the same way the shape recognizer does.
public protocol ThunkEvaluationEnvironment {
    func callee(at address: UInt64) -> ThunkCallee
    /// The address stored at `address`, with any rebase applied; `nil` when
    /// the word is not a pointer the environment can read.
    func pointer(at address: UInt64) -> UInt64?
    /// The symbol the pointer-sized slot at `address` binds to or rebases
    /// onto (a GOT slot's), when the environment can name it.
    func slotSymbolName(at address: UInt64) -> String?
}

/// Knows nothing: every call is unknown, every word unreadable. What the
/// shape recognizer used before construction could be read, and what its
/// synthesized-sequence tests still run against.
public struct EmptyThunkEvaluationEnvironment: ThunkEvaluationEnvironment {
    public init() {}
    public func callee(at address: UInt64) -> ThunkCallee { .unknown }
    public func pointer(at address: UInt64) -> UInt64? { nil }
    public func slotSymbolName(at address: UInt64) -> String? { nil }
}

#endif
