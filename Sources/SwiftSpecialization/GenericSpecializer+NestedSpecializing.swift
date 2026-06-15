import MachOKit

/// `GenericSpecializer` already exposes `makeRequest(for:candidateOptions:)`
/// and `specialize(_:with:metadataRequest:)` with signatures matching
/// `NestedSpecializing`, so the conformance is purely a declaration that lets
/// `TypeDefinition`'s nested-child derivation (the `specialize(...)` extension
/// in this module) drive specialization through this engine via the
/// `NestedSpecializing` abstraction.
// `specialize(_:with:metadataRequest:)` is only available on the in-process
// `MachOImage` engine (runtime metadata resolution needs process memory), so
// the conformance is constrained to match — which is exactly where
// `TypeDefinition`'s nested-specialization derivation operates.
extension GenericSpecializer: NestedSpecializing where MachO == MachOImage {}
