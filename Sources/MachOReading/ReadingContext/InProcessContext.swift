import MachOKit
import MachOExtensions

/// A reading context for direct in-process memory access.
///
/// `InProcessContext` provides zero-copy memory access using `UnsafeRawPointer`
/// as addresses. This is the most efficient way to read data when working with
/// memory that's already loaded in the current process.
///
/// ## Usage
///
/// ```swift
/// let ptr: UnsafeRawPointer = ...
/// let context = InProcessContext.shared
///
/// // Read data directly from memory
/// let descriptor: ProtocolDescriptor = try context.readWrapperElement(at: ptr)
/// ```
///
/// ## Address Type
///
/// `InProcessContext` uses `UnsafeRawPointer` as its address type, allowing
/// direct memory operations without any copying or offset calculations.
///
/// ## Thread Safety
///
/// `InProcessContext` is stateless and can be safely shared across threads.
/// The `shared` singleton is recommended for most use cases.
///
/// Note: This type is marked as `@unchecked Sendable` because `UnsafeRawPointer`
/// is not `Sendable`. Thread safety must be ensured by the caller when using
/// addresses across thread boundaries.
public struct InProcessContext: ReadingContext, Sendable {
    /// The runtime target for in-process access.
    public typealias Runtime = InProcess

    /// Addresses are raw memory pointers.
    public typealias Address = UnsafeRawPointer

    /// A shared singleton instance.
    ///
    /// Since `InProcessContext` is stateless, using a shared instance
    /// avoids unnecessary allocations.
    public static let shared = InProcessContext()

    /// Creates a new in-process reading context.
    public init() {}

    public func readElement<T>(at ptr: Address) throws -> T {
        try ptr.stripPointerTags().readElement()
    }

    public func readElements<T>(at ptr: Address, numberOfElements: Int) throws -> [T] {
        try ptr.stripPointerTags().readElements(numberOfElements: numberOfElements)
    }
    
    public func readWrapperElement<T: LocatableLayoutWrapper>(at ptr: Address) throws -> T {
        try ptr.stripPointerTags().readWrapperElement()
    }
    
    public func readWrapperElements<T>(at ptr: Address, numberOfElements: Int) throws -> [T] where T : LocatableLayoutWrapper {
        try ptr.stripPointerTags().readWrapperElements(numberOfElements: numberOfElements)
    }

    public func readString(at ptr: Address) throws -> String {
        try ptr.stripPointerTags().readString()
    }

    public func advanceAddress(_ address: Address, by delta: Int) -> Address {
        address.advanced(by: delta)
    }
    
    public func advanceAddress<T>(_ address: Address, of type: T.Type) -> Address {
        address.advanced(by: MemoryLayout<T>.size)
    }

    public func addressFromOffset(_ offset: Int) throws -> Address {
        // For InProcess context, the offset is a pointer bit pattern
        try UnsafeRawPointer(bitPattern: offset)
    }

    public func addressFromVirtualAddress(_ virtualAddress: UInt64) throws -> Address {
        // For InProcess context, the virtual address is a pointer bit pattern
        // Use UInt for the intermediate conversion to handle large addresses correctly
        try UnsafeRawPointer(bitPattern: UInt(virtualAddress)).stripPointerTags()
    }
    
    public func offsetFromAddress(_ address: Address) throws -> Int {
        Int(bitPattern: address)
    }
}
