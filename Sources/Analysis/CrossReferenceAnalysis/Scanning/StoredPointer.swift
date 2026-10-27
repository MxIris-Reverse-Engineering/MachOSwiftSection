import MachOFoundation

/// A pointer as this process keeps it in memory: a GOT slot, a selector
/// reference, a class list entry, the `isa` of a class, a metadata record's
/// descriptor field. Above the address it may carry an arm64e signature or
/// tag bits.
enum StoredPointer {
    /// The address `value` holds, its signature and tag bits stripped.
    ///
    /// Which bits are the address depends on the platform — a Mac's user
    /// addresses fit in 47 bits, an iPhone's in 36, and an arm64e signature
    /// starts right above the address — so the mask is the one
    /// `InProcessContext` takes from the running process, never a constant.
    /// A 47-bit constant left an iPhone's signature bits 39–46 in place, and
    /// every signed slot read there led nowhere.
    static func address(in value: UInt64) -> UInt {
        UInt(truncatingIfNeeded: value) & InProcessContext.addressMask
    }
}
