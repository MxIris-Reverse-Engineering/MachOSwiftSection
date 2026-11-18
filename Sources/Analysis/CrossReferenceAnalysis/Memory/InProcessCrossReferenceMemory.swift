import MachOFoundation

/// The current process's memory, read where it lies: an address is a
/// pointer, and a slot holds what dyld bound or rebased into it — lazy
/// pointers included, since dyld binds every slot when it loads an image
/// (macOS 27.2, `LazyBindingTests`).
///
/// The only file of the module that turns an address into a pointer
/// (`crossReferenceAnalysisReadsMemoryOnlyThroughCrossReferenceMemory`).
package struct InProcessCrossReferenceMemory: CrossReferenceMemory {
    package init() {}

    package func bytes(at address: UInt, length: Int) -> UnsafeRawBufferPointer? {
        guard length >= 0, let start = UnsafeRawPointer(bitPattern: address) else { return nil }
        return UnsafeRawBufferPointer(start: start, count: length)
    }

    package func slotContent(at address: UInt) -> SlotContent? {
        guard let slot = UnsafeRawPointer(bitPattern: address) else { return nil }
        return .address(UInt(truncatingIfNeeded: slot.loadUnaligned(as: UInt64.self)) & addressMask)
    }

    /// Which bits are the address depends on the platform — a Mac's user
    /// addresses fit in 47 bits, an iPhone's in 36, and an arm64e signature
    /// starts right above the address — so the mask is the one
    /// `InProcessContext` takes from the running process, never a constant.
    /// A 47-bit constant left an iPhone's signature bits 39–46 in place, and
    /// every signed slot read there led nowhere.
    package var addressMask: UInt {
        InProcessContext.addressMask
    }
}
