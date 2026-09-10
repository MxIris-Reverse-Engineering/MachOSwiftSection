import Foundation
import MachOKit
import MachOBase

/// The record a callee-allocated coroutine gets alongside its body, symbol
/// `…Twc`.
///
/// This is ``AsyncFunctionPointer``'s counterpart for `yield_once_2`
/// coroutines — the calling convention behind `_read` / `_modify` accessors
/// once the CoroutineAccessors feature is on. The caller allocates the
/// coroutine's frame, so it must know the frame size before entering, and
/// again that fact is not recoverable from the entry point. IRGen therefore
/// emits this record and hands out *its* address wherever a normal function's
/// address would go: a method descriptor, vtable slot, resilient witness or
/// protocol requirement whose implementation is such a coroutine stores a
/// relative pointer to here (`swift/lib/IRGen/GenMeta.cpp`, the
/// `isCalleeAllocatedCoroutine()` branch), so its `implementationOffset` lands
/// one hop short of the machine code.
///
/// Unlike ``AsyncFunctionPointer`` this record has **no counterpart type in
/// `swift/include/swift/ABI/`** — like a property descriptor, it exists only
/// in IRGen, as the anonymous struct `swift.coro_func_pointer`
/// (`IRGenModule.cpp` builds the type, `GenMeta.cpp`'s
/// `emitCoroFunctionPointer` fills it). It is emitted packed; on 64-bit
/// Darwin the fields are naturally aligned anyway, so the packed and unpacked
/// layouts coincide at 16 bytes.
///
/// There is no section listing these records — they live in `__TEXT,__const`
/// and are reached by symbol or by another descriptor's relative pointer, so
/// the only entry is `CoroFunctionPointer.resolve(from:in:)`.
public struct CoroFunctionPointer: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let function: RelativeDirectRawPointer
        public let allocationSize: UInt32
        public let mallocTypeIdentifier: UInt64
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

extension CoroFunctionPointer {
    /// File offset of the coroutine's entry point, or `nil` when the pointer
    /// is null. Pure pointer arithmetic on the record's own offset — no
    /// reader involved, same contract as
    /// ``MethodDescriptor/implementationOffset``.
    public var functionOffset: Int? {
        guard layout.function.isValid else { return nil }
        return layout.function.resolveDirectOffset(from: offset(of: \.function))
    }

    /// Size in bytes of the coroutine frame the caller must allocate before
    /// entering the coroutine.
    public var allocationSize: UInt32 {
        layout.allocationSize
    }

    /// The typed-allocation identifier IRGen derives for this coroutine's
    /// frame (`IRGenModule::getMallocTypeId`). Zero when the build emits no
    /// typed-allocation metadata; this layer reports the raw word and does not
    /// interpret it.
    public var mallocTypeIdentifier: UInt64 {
        layout.mallocTypeIdentifier
    }
}

// MARK: - ReadingContext Support

extension CoroFunctionPointer {
    /// The entry point's location as an address in `context` (a file offset
    /// for `MachOContext`, a pointer in-process), or `nil` for a null pointer.
    public func functionAddress<Context: ReadingContext>(in context: Context) throws -> Context.Address? {
        guard let functionOffset else { return nil }
        return try context.addressFromOffset(functionOffset)
    }
}
