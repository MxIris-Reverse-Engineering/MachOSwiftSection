import MachOKit
import MachOExtensions

/// A reading context for MachO files and images.
///
/// `MachOContext` wraps a MachO file or image and provides a unified
/// interface for reading data using file offsets as addresses.
///
/// ## Usage
///
/// ```swift
/// let machO: MachOFile = ...
/// let context = MachOContext(machO)
///
/// // Or use the convenience property
/// let context = machO.context
///
/// // Read data using the context
/// let descriptor: ProtocolDescriptor = try context.readWrapperElement(at: offset)
/// ```
///
/// ## Address Type
///
/// `MachOContext` uses `Int` as its address type, representing file offsets.
/// This allows relative pointer resolution to work correctly with file-based
/// data.
public struct MachOContext<MachO: MachORepresentableWithCache & Readable>: ReadingContext, Sendable {
    /// The runtime target is always 64-bit for MachO contexts.
    /// TODO: Support 32-bit MachO files by checking the header.
    public typealias Runtime = RuntimeTarget64

    /// Addresses are file offsets.
    public typealias Address = Int

    /// The underlying MachO file or image.
    public let machO: MachO

    /// Creates a new MachO reading context.
    ///
    /// - Parameter machO: The MachO file or image to read from
    public init(_ machO: MachO) {
        self.machO = machO
    }

    public func readElement<T>(at offset: Int) throws -> T {
        try machO.readElement(offset: offset)
    }

    public func readElements<T>(at address: Int, numberOfElements: Int) throws -> [T] {
        try machO.readElements(offset: address, numberOfElements: numberOfElements)
    }

    public func readWrapperElement<T: LocatableLayoutWrapper>(at offset: Int) throws -> T {
        try machO.readWrapperElement(offset: offset)
    }

    public func readWrapperElements<T>(at address: Int, numberOfElements: Int) throws -> [T] where T: LocatableLayoutWrapper {
        try machO.readWrapperElements(offset: address, numberOfElements: numberOfElements)
    }

    public func readString(at offset: Int) throws -> String {
        try machO.readString(offset: offset)
    }

    public func advanceAddress(_ offset: Int, by delta: Int) -> Int {
        offset + delta
    }

    public func advanceAddress<T>(_ address: Int, of type: T.Type) -> Int {
        address.offseting(of: type)
    }

    public func addressFromOffset(_ offset: Int) throws -> Int {
        offset
    }

    public func addressFromVirtualAddress(_ virtualAddress: UInt64) throws -> Int {
        machO.resolveOffset(at: machO.stripPointerTags(of: virtualAddress)).cast()
    }

    public func offsetFromAddress(_ address: Int) throws -> Int {
        address
    }
}

// MARK: - Convenience Extensions

extension MachORepresentableWithCache where Self: Readable {
    /// Returns a reading context for this MachO file or image.
    ///
    /// This is a convenience property that wraps `self` in a `MachOContext`.
    ///
    /// ```swift
    /// let machO: MachOFile = ...
    /// let name = try descriptor.layout.name.resolve(
    ///     from: descriptor.offset(of: \.name),
    ///     in: machO.context
    /// )
    /// ```
    public var context: MachOContext<Self> {
        MachOContext(self)
    }
}
