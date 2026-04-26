import MachOKit

/// Exposes dyld bind / rebase resolution capabilities required when decoding
/// indirect symbolic references in Swift metadata.
///
/// `SymbolOrElementPointer` and other indirect-pointer readers must consult
/// this protocol before treating the bytes at a relocation site as a literal
/// virtual address. For files coming straight from disk the bytes are still
/// chained-fixup encoded; only after binding/rebasing through the dyld
/// metadata do they become a usable address.
///
/// The protocol exists so the resolver code can stay generic over the reading
/// context and not hard-code `MachOFile`. Wrapper types (e.g. UI-layer
/// projections that compose a `MachOFile` plus extra state) just forward to
/// the underlying `MachOFile` to participate in the same dispatch.
public protocol MachOBindRebaseResolving: Sendable {
    /// Resolves a bind operation at the given file offset and returns the
    /// imported symbol name, or `nil` when the offset is not bound.
    func resolveBind(fileOffset: Int) -> String?

    /// Resolves a rebase operation at the given file offset and returns the
    /// rebased absolute address, or `nil` when no rebase is recorded.
    func resolveRebase(fileOffset: Int) -> UInt64?
}

extension MachOFile: MachOBindRebaseResolving {}
