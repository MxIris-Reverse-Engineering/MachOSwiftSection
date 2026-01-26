import MachOKit
import MachOExtensions

/// A protocol for types that can read binary data from a backing store.
///
/// `Readable` provides a unified interface for reading elements, arrays, and strings
/// from different sources (files, memory, etc.) using byte offsets.
///
/// ## Overview
///
/// This protocol abstracts the reading operations needed to parse MachO data structures.
/// Conforming types include:
/// - `MachOFile`: Reads from disk via file I/O
/// - `MachOImage`: Reads from memory-mapped images
/// - `UnsafeRawPointer`: Reads directly from memory
///
/// ## Reading Elements
///
/// There are two variants for reading elements:
/// - `readElement`: Reads raw bytes and interprets them as the target type
/// - `readWrapperElement`: Reads a layout and wraps it with location information
///
/// ## Example
///
/// ```swift
/// // Read a raw struct from a MachO file
/// let header: mach_header_64 = try machOFile.readElement(offset: 0)
///
/// // Read a descriptor that remembers its location
/// let descriptor: ProtocolDescriptor = try machOFile.readWrapperElement(offset: offset)
/// print(descriptor.offset) // The offset where this was read from
/// ```
public protocol Readable {
    /// Reads a single element from the given offset.
    ///
    /// - Parameter offset: The byte offset to read from
    /// - Returns: The element read and interpreted as type `Element`
    /// - Throws: If reading fails
    func readElement<Element>(offset: Int) throws -> Element

    /// Reads a layout wrapper element from the given offset.
    ///
    /// This method reads the layout bytes and creates a wrapper that remembers
    /// its location (offset), enabling relative pointer resolution.
    ///
    /// - Parameter offset: The byte offset to read from
    /// - Returns: The wrapper element with location information
    /// - Throws: If reading fails
    func readWrapperElement<Element>(offset: Int) throws -> Element where Element: LocatableLayoutWrapper

    /// Reads multiple elements starting from the given offset.
    ///
    /// Elements are read sequentially with each element's size determining
    /// the offset for the next element.
    ///
    /// - Parameters:
    ///   - offset: The byte offset to start reading from
    ///   - numberOfElements: The number of elements to read
    /// - Returns: An array of elements read sequentially
    /// - Throws: If reading fails
    func readElements<Element>(offset: Int, numberOfElements: Int) throws -> [Element]

    /// Reads multiple layout wrapper elements starting from the given offset.
    ///
    /// Each wrapper element remembers its individual offset, enabling
    /// relative pointer resolution for each element.
    ///
    /// - Parameters:
    ///   - offset: The byte offset to start reading from
    ///   - numberOfElements: The number of elements to read
    /// - Returns: An array of wrapper elements with location information
    /// - Throws: If reading fails
    func readWrapperElements<Element>(offset: Int, numberOfElements: Int) throws -> [Element] where Element: LocatableLayoutWrapper

    /// Reads a null-terminated C string from the given offset.
    ///
    /// - Parameter offset: The byte offset to read from
    /// - Returns: The string read from the data
    /// - Throws: If reading fails or the string is not valid UTF-8
    func readString(offset: Int) throws -> String
}
