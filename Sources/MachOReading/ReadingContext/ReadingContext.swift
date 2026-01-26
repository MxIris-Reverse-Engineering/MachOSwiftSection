import MachOKit
import MachOExtensions

/// A protocol for address types that support arithmetic operations.
///
/// This enables generic code to perform pointer arithmetic without
/// knowing the concrete address type (Int for file offsets, UnsafeRawPointer for memory).
///
/// ## Conforming Types
///
/// - `Int`: Used for file offsets in external MachO reading
/// - `UnsafeRawPointer`: Used for direct memory access in in-process reading
///
/// ## Example
///
/// ```swift
/// func computeOffset<Address: AddressArithmetic>(
///     from base: Address,
///     to current: Address
/// ) -> Int {
///     current - base  // Returns the byte distance
/// }
///
/// func advance<Address: AddressArithmetic>(
///     _ address: Address,
///     by offset: Int
/// ) -> Address {
///     address + offset  // Returns a new address
/// }
/// ```
public protocol AddressArithmetic {
    /// Returns a new address by adding an offset to the base address.
    ///
    /// - Parameters:
    ///   - lhs: The base address
    ///   - rhs: The byte offset to add
    /// - Returns: A new address offset by the given amount
    static func + (lhs: Self, rhs: Int) -> Self

    /// Returns a new address by adding an offset to the base address (reversed operands).
    ///
    /// - Parameters:
    ///   - lhs: The byte offset to add
    ///   - rhs: The base address
    /// - Returns: A new address offset by the given amount
    static func + (lhs: Int, rhs: Self) -> Self

    /// Returns a new address by subtracting an offset from the base address.
    ///
    /// - Parameters:
    ///   - lhs: The base address
    ///   - rhs: The byte offset to subtract
    /// - Returns: A new address offset by the given amount
    static func - (lhs: Self, rhs: Int) -> Self

    /// Computes the byte distance between two addresses.
    ///
    /// - Parameters:
    ///   - lhs: The end address
    ///   - rhs: The start address
    /// - Returns: The number of bytes from `rhs` to `lhs` (can be negative)
    static func - (lhs: Self, rhs: Self) -> Int

    /// Advances the address in place by adding an offset.
    ///
    /// - Parameters:
    ///   - lhs: The address to modify
    ///   - rhs: The byte offset to add
    static func += (lhs: inout Self, rhs: Int)

    /// Moves the address backward in place by subtracting an offset.
    ///
    /// - Parameters:
    ///   - lhs: The address to modify
    ///   - rhs: The byte offset to subtract
    static func -= (lhs: inout Self, rhs: Int)
}

// MARK: - AddressArithmetic Conformances

extension Int: AddressArithmetic {}
extension UnsafeRawPointer: AddressArithmetic {}

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
    associatedtype Address: AddressArithmetic

    /// Reads a raw element from the given address.
    ///
    /// - Parameter address: The address to read from
    /// - Returns: The element read from memory/file
    /// - Throws: If reading fails
    func readElement<T>(at address: Address) throws -> T

    /// Reads multiple elements starting from the given address.
    ///
    /// Elements are read sequentially, with each element's size determining
    /// the address for the next element.
    ///
    /// - Parameters:
    ///   - address: The address to start reading from
    ///   - numberOfElements: The number of elements to read
    /// - Returns: An array of elements read sequentially
    /// - Throws: If reading fails
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

    /// Reads multiple layout wrapper elements starting from the given address.
    ///
    /// Each wrapper element remembers its individual address/offset, enabling
    /// relative pointer resolution for each element.
    ///
    /// - Parameters:
    ///   - address: The address to start reading from
    ///   - numberOfElements: The number of elements to read
    /// - Returns: An array of wrapper elements with location information
    /// - Throws: If reading fails
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

    /// Advances an address by the size of the given type.
    ///
    /// This is equivalent to `advanceAddress(address, by: MemoryLayout<T>.size)`
    /// and is useful when iterating through arrays of elements.
    ///
    /// - Parameters:
    ///   - address: The base address
    ///   - type: The type whose size determines the advancement
    /// - Returns: The address advanced by the type's size
    func advanceAddress<T>(_ address: Address, of type: T.Type) -> Address

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

    /// Converts this context's address to an integer offset.
    ///
    /// This is the inverse operation of `addressFromOffset` and is used when
    /// an integer offset is needed (e.g., for symbol binding lookups).
    ///
    /// - For `MachOContext`: Returns the address as-is (since `Address = Int`)
    /// - For `InProcessContext`: Returns the pointer's bit pattern as `Int`
    ///
    /// - Parameter address: The address to convert
    /// - Returns: The integer offset representation
    /// - Throws: If the address cannot be converted
    func offsetFromAddress(_ address: Address) throws -> Int
}
