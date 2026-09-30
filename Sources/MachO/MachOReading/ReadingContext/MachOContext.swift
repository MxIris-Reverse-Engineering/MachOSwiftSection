import MachOKit
import MachOKitExtensions

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

    public func addressFromOffset(_ offset: Int) -> Int {
        offset
    }

    /// Never throws: every reader resolves any virtual address to some
    /// offset. The reader strips pointer tags itself — `MachOFile` inside
    /// `fileOffset(of:)`, `MachOImage` in `resolveOffset(at:)` — so they are
    /// not stripped a second time here.
    public func addressFromVirtualAddress(_ virtualAddress: UInt64) -> Int {
        machO.resolveOffset(at: virtualAddress)
    }

    public func offsetFromAddress(_ address: Int) -> Int {
        address
    }

    /// Vends the underlying MachO object as a bind/rebase resolver when it
    /// conforms to `MachOBindRebaseResolving`. The runtime cast keeps the
    /// generic parameter `MachO` unconstrained, so wrapper types (e.g.
    /// UI-layer projections that compose a `MachOFile`) can opt in by
    /// declaring conformance themselves without changing this site.
    public var bindRebaseResolver: (any MachOBindRebaseResolving)? {
        machO as? any MachOBindRebaseResolving
    }

    /// Offsets are per image, so memo entries belong to this image: keyed on
    /// the reader's identifier, the key its other per-image caches use.
    public var cacheScope: ReadingContextCacheScope {
        .image(identifier: AnyHashable(machO.identifier))
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

// MARK: - Runtime Pointer Support

extension MachOContext {
    /// Returns the runtime pointer for the given file offset when the
    /// underlying reader is a `MachOImage` mapped into the current process.
    /// Returns `nil` for `MachOFile` and other non-resident readers.
    public func runtimePointer(at address: Int) throws -> UnsafeRawPointer? {
        if let machOImage = machO as? MachOImage {
            return machOImage.ptr + UnsafeRawPointer.Stride(address)
        }
        return nil
    }
}

extension ReadingContext where Self == MachOContext<MachOFile> {
    public static func machOFile(_ machO: MachOFile) -> Self {
        .init(machO)
    }
}

extension ReadingContext where Self == MachOContext<MachOImage> {
    public static func machOImage(_ machO: MachOImage) -> Self {
        .init(machO)
    }
}
