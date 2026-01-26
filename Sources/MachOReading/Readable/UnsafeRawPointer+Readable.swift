import MachOKit
import MachOExtensions

/// Extends `UnsafeRawPointer` to conform to `Readable`, enabling direct memory reading.
///
/// This extension allows reading data directly from memory addresses, which is
/// useful for in-process Swift runtime introspection where metadata is already
/// loaded in the current process's address space.
///
/// ## Offset vs Direct Reading
///
/// This extension provides two sets of methods:
/// - **Offset-based**: `readElement(offset:)` - reads relative to the pointer
/// - **Direct**: `readElement()` - reads at the pointer's current location
///
/// ## Pointer Tags
///
/// The implementation handles ARM64 pointer authentication tags by stripping
/// them before reading. This ensures compatibility with PAC-enabled systems.
///
/// ## Example
///
/// ```swift
/// let ptr: UnsafeRawPointer = ...
///
/// // Read at the pointer location
/// let flags: ContextDescriptorFlags = try ptr.readElement()
///
/// // Read at an offset from the pointer
/// let name: String = try ptr.readString(offset: 4)
///
/// // Read with wrapper (uses bit pattern as offset for InProcess context)
/// let descriptor: ProtocolDescriptor = try ptr.readWrapperElement()
/// ```
extension UnsafeRawPointer: Readable {
    public func readElement<Element>(offset: Int) throws -> Element {
        try advanced(by: offset).readElement()
    }

    public func readWrapperElement<Element>(offset: Int) throws -> Element where Element: MachOExtensions.LocatableLayoutWrapper {
        try advanced(by: offset).readWrapperElement()
    }

    public func readElements<Element>(offset: Int, numberOfElements: Int) throws -> [Element] {
        try advanced(by: offset).readElements(numberOfElements: numberOfElements)
    }

    public func readWrapperElements<Element>(offset: Int, numberOfElements: Int) throws -> [Element] where Element: MachOExtensions.LocatableLayoutWrapper {
        try advanced(by: offset).readWrapperElements(numberOfElements: numberOfElements)
    }

    public func readString(offset: Int) throws -> String {
        try advanced(by: offset).readString()
    }

    public func readElement<Element>() throws -> Element {
        return assumingMemoryBound(to: Element.self).pointee
    }

    public func readWrapperElement<Element>() throws -> Element where Element: LocatableLayoutWrapper {
        let layout: Element.Layout = assumingMemoryBound(to: Element.Layout.self).pointee
        return .init(layout: layout, offset: box.bitPattern.int)
    }

    public func readElements<Element>(to: Element.Type = Element.self, numberOfElements: Int) throws -> [Element] {
        return MemorySequence<Element>(basePointer: assumingMemoryBound(to: Element.self), numberOfElements: numberOfElements).map { $0 }
    }

    public func readWrapperElements<Element>(to: Element.Type = Element.self, numberOfElements: Int) throws -> [Element] where Element: LocatableLayoutWrapper {
        var currentOffset = box.bitPattern.int
        let elements = MemorySequence<Element.Layout>(basePointer: assumingMemoryBound(to: Element.Layout.self), numberOfElements: numberOfElements).map { (layout: Element.Layout) -> Element in
            let element = Element(layout: layout, offset: currentOffset)
            currentOffset += Element.layoutSize
            return element
        }
        return elements
    }

    public func readString() throws -> String {
        return .init(cString: assumingMemoryBound(to: CChar.self))
    }
}
