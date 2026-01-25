import MachOKit
import MachOExtensions

/// A unified protocol for reading data from different sources.
///
/// `ReadingContext` abstracts the differences between:
/// - **External reading**: Reading from MachO files via file I/O (using offsets)
/// - **InProcess reading**: Direct memory access via pointers
///
/// This design is inspired by Swift Runtime's `MemoryReader` abstraction
/// (see `swift/include/swift/Remote/MemoryReader.h`).
///
/// ## Overview
///
/// The key insight is that both reading modes share the same operations:
/// - Read an element at an address
/// - Read a string at an address
/// - Advance an address by a relative offset
///
/// The difference is in the `Address` type:
/// - MachO: `Address = Int` (file offset)
/// - InProcess: `Address = UnsafeRawPointer` (memory pointer)
///
/// ## Example
///
/// ```swift
/// // Generic function that works with any ReadingContext
/// func readDescriptor<Context: ReadingContext>(
///     at address: Context.Address,
///     in context: Context
/// ) throws -> ProtocolDescriptor {
///     try ProtocolDescriptor.resolve(at: address, in: context)
/// }
///
/// // Use with MachO file
/// let desc1 = try readDescriptor(at: offset, in: machO.context)
///
/// // Use with in-process memory
/// let desc2 = try readDescriptor(at: ptr, in: InProcessContext.shared)
/// ```
public protocol ReadingContext: Sendable {
    /// The runtime target this context operates on.
    associatedtype Runtime: RuntimeProtocol

    /// The address type used by this context.
    /// - MachO contexts use `Int` (file offset)
    /// - InProcess contexts use `UnsafeRawPointer`
    ///
    /// Note: `Address` does not require `Sendable` because `UnsafeRawPointer`
    /// is not `Sendable` in Swift's concurrency model. Thread safety must be
    /// ensured by the caller when using `InProcessContext`.
    associatedtype Address

    /// Reads a raw element from the given address.
    ///
    /// - Parameter address: The address to read from
    /// - Returns: The element read from memory/file
    /// - Throws: If reading fails
    func readElement<T>(at address: Address) throws -> T
    
    
    func readElements<T>(at address: Address, numberOfElements: Int) throws -> [T]

    /// Reads a layout wrapper element from the given address.
    ///
    /// This method reads the layout and creates a wrapper that remembers
    /// its location (offset or pointer).
    ///
    /// - Parameter address: The address to read from
    /// - Returns: The wrapper element with location information
    /// - Throws: If reading fails
    func readWrapperElement<T: LocatableLayoutWrapper>(at address: Address) throws -> T
    
    func readWrapperElements<T: LocatableLayoutWrapper>(at address: Address, numberOfElements: Int) throws -> [T]

    /// Reads a null-terminated C string from the given address.
    ///
    /// - Parameter address: The address to read from
    /// - Returns: The string read from memory/file
    /// - Throws: If reading fails
    func readString(at address: Address) throws -> String

    /// Computes a new address by applying a relative offset.
    ///
    /// This is used for resolving relative pointers:
    /// `newAddress = baseAddress + relativeOffset`
    ///
    /// - Parameters:
    ///   - address: The base address
    ///   - offset: The relative offset to add
    /// - Returns: The computed address
    func advanceAddress(_ address: Address, by offset: Int) -> Address

    /// Converts an integer offset (typically a pointer bit pattern) to this context's address type.
    ///
    /// This is used when working with `MangledName` lookup elements, which store
    /// offsets as integers regardless of the context type.
    ///
    /// - For `MachOContext`: Returns the offset as-is (since `Address = Int`)
    /// - For `InProcessContext`: Converts to `UnsafeRawPointer`
    ///
    /// - Parameter offset: The integer offset to convert
    /// - Returns: The address in this context's address type
    /// - Throws: If the offset cannot be converted to a valid address
    func addressFromOffset(_ offset: Int) throws -> Address

    /// Converts a virtual address (UInt64) to this context's address type.
    ///
    /// This is used when working with pointer types that store absolute virtual
    /// addresses, such as `SymbolOrElementPointer`.
    ///
    /// - For `MachOContext`: Converts virtual address to file offset
    /// - For `InProcessContext`: Converts to `UnsafeRawPointer` via bit pattern
    ///
    /// - Parameter virtualAddress: The virtual address to convert
    /// - Returns: The address in this context's address type
    /// - Throws: If the address cannot be converted
    func addressFromVirtualAddress(_ virtualAddress: UInt64) throws -> Address
}
