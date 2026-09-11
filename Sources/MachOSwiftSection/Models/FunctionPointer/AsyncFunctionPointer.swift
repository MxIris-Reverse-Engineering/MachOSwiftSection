import Foundation
import MachOKit
import MachOBase

/// The record every `async` function gets alongside its body, symbol `…Tu`.
///
/// An async function is not called through its own address: the caller needs
/// to know how much async context to allocate before it can start, and that
/// size is not recoverable from the entry point. So the compiler emits this
/// two-word constant next to the function and hands *its* address out
/// wherever a normal function would have handed out the body's.
///
/// That substitution is why this type matters to a reader of Mach-O metadata.
/// A method descriptor, a vtable slot, a resilient witness and a protocol
/// requirement's default implementation all store a relative pointer to the
/// implementation — but IRGen writes the address of this record instead
/// whenever the implementation is async (`swift/lib/IRGen/GenMeta.cpp`,
/// `MethodDescriptorBuilder::addImpl` and friends, which branch on
/// `impl->isAsync()`). Their `implementationOffset` therefore lands here, one
/// hop short of the machine code; `functionOffset` is that last hop.
///
/// Layout mirrors `swift::AsyncFunctionPointer` (`swift/ABI/Executor.h`).
/// There is no section listing these records — they live in `__TEXT,__const`
/// and are reached by symbol or by another descriptor's relative pointer, so
/// the only entry is `AsyncFunctionPointer.resolve(from:in:)` with an offset
/// the caller already has. See also ``CoroFunctionPointer``, the same idea for
/// callee-allocated coroutines.
public struct AsyncFunctionPointer: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        /// The async function's entry point.
        public let function: RelativeDirectRawPointer
        /// Size in bytes of the async context frame the caller must
        /// allocate before entering the function.
        public let expectedContextSize: UInt32
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

// MARK: - ReadingContext Support

extension AsyncFunctionPointer {
    /// The entry point's location as an address in `context` (a file offset
    /// for `MachOContext`, a pointer in-process), or `nil` for a null pointer.
    public func functionAddress<Context: ReadingContext>(in context: Context) throws -> Context.Address? {
        guard let functionOffset = resolvedDirectOffset(from: \.function) else { return nil }
        return try context.addressFromOffset(functionOffset)
    }
}
