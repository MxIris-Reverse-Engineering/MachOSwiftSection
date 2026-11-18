/// What a pointer slot holds, once whatever the binary stores there is
/// decoded: an address in the analyzer's address space, or the name of the
/// symbol the slot is bound to when no image the analyzer covers exports it.
package enum SlotContent: Hashable, Sendable {
    case address(UInt)
    case importedSymbol(String)
}

/// Where an analyzer reads the bytes of the images it covers, by their
/// addresses in its own address space — the runtime addresses of the current
/// process for the in-process analyzer.
///
/// Every read of image memory goes through here, so that an analyzer can
/// read images that were never loaded. What differs between the two kinds of
/// memory is what a pointer slot holds: in the process, dyld has bound and
/// rebased it, and the value is read as it stands; in a file, it is a fixup
/// that has to be decoded. Raw bytes — instructions, strings, the integer
/// fields of a structure — read the same in both.
package protocol CrossReferenceMemory: Sendable {
    /// The `length` bytes from `address` on, contiguous and read-only, or
    /// `nil` when they cannot be read.
    ///
    /// The in-process memory does not check that they are mapped: it trusts
    /// the caller, as every read did before it existed, and a caller that
    /// may hold an unmapped address asks the analyzer's `isMapped` first.
    func bytes(at address: UInt, length: Int) -> UnsafeRawBufferPointer?

    /// What the pointer slot at `address` holds, its signature and tag bits
    /// stripped; `nil` when it cannot be read.
    func slotContent(at address: UInt) -> SlotContent?

    /// The bits of a stored pointer that are its address: the rest carry an
    /// arm64e signature or tag bits.
    var addressMask: UInt { get }

    /// The addresses `count` consecutive pointer slots from `address` on
    /// hold, 0 for a slot that holds none: what a pass over a whole section
    /// of slots — an image's selector references — reads in one call
    /// rather than one call a slot.
    func pointers(inSlotsAt address: UInt, count: Int) -> [UInt]

    /// Where each of `addresses` can be read from, `nil` for 0 or one that
    /// cannot: for a pass that reads a string at each address a section's
    /// slots hold, in one call rather than one call an address. How far each
    /// may be read is the caller's to know.
    func readablePointers(at addresses: [UInt]) -> [UnsafeRawPointer?]
}

extension CrossReferenceMemory {
    /// One ``slotContent(at:)`` a slot.
    package func pointers(inSlotsAt address: UInt, count: Int) -> [UInt] {
        (0 ..< count).map { pointer(at: address &+ UInt($0 * 8)) ?? 0 }
    }

    /// One ``bytes(at:length:)`` an address.
    package func readablePointers(at addresses: [UInt]) -> [UnsafeRawPointer?] {
        addresses.map { $0 == 0 ? nil : bytes(at: $0, length: 1)?.baseAddress }
    }

    /// The value of type `type` stored at `address`, read unaligned.
    package func load<Value>(_ type: Value.Type, at address: UInt) -> Value? {
        guard let buffer = bytes(at: address, length: MemoryLayout<Value>.size) else { return nil }
        let value: Value = buffer.loadUnaligned(as: Value.self)
        return value
    }

    /// The address the pointer slot at `address` holds; `nil` when it holds
    /// a symbol no image defines, or cannot be read.
    package func pointer(at address: UInt) -> UInt? {
        guard case .address(let target)? = slotContent(at: address) else { return nil }
        return target
    }

    /// The start of the bytes at `address`, typed, for a caller that reads a
    /// string or an array from there and has bounded how far it reads.
    package func typedPointer<Element>(to type: Element.Type, at address: UInt, length: Int) -> UnsafePointer<Element>? {
        bytes(at: address, length: length)?.baseAddress?.assumingMemoryBound(to: Element.self)
    }
}
