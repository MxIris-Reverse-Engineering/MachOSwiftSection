import MachOKit
import MachOExtensions

/// Extends `MachOImage` to conform to `Readable`, enabling memory-based reading.
///
/// This extension provides direct memory access for MachO images that are
/// already loaded in memory (e.g., via `dlopen` or the dyld image list).
///
/// ## Performance
///
/// Since `MachOImage` operates on memory-mapped data, reads are essentially
/// pointer dereferences with no additional I/O overhead.
///
/// ## Example
///
/// ```swift
/// let machOImage: MachOImage = ...
///
/// // Read a raw element from memory
/// let header: mach_header_64 = try machOImage.readElement(offset: 0)
///
/// // Read with wrapper (preserves offset for relative pointer resolution)
/// let descriptor: ProtocolDescriptor = try machOImage.readWrapperElement(offset: offset)
/// ```
extension MachOImage: Readable {
    public func readElement<Element>(
        offset: Int
    ) throws -> Element {
        let pointer = ptr + offset
        return pointer.assumingMemoryBound(to: Element.self).pointee
    }

    public func readElement<Element>(
        offset: Int
    ) throws -> Element where Element: LocatableLayoutWrapper {
        return try readWrapperElement(offset: offset)
    }

    public func readWrapperElement<Element>(offset: Int) throws -> Element where Element: LocatableLayoutWrapper {
        let pointer = ptr + offset
        let layout: Element.Layout = pointer.assumingMemoryBound(to: Element.Layout.self).pointee
        return .init(layout: layout, offset: offset)
    }

    public func readElements<Element>(
        offset: Int,
        numberOfElements: Int
    ) throws -> [Element] {
        let pointer = ptr + offset
        return MemorySequence<Element>(basePointer: pointer.assumingMemoryBound(to: Element.self), numberOfElements: numberOfElements).map { $0 }
    }

    public func readElements<Element>(
        offset: Int,
        numberOfElements: Int
    ) throws -> [Element] where Element: LocatableLayoutWrapper {
        return try readWrapperElements(offset: offset, numberOfElements: numberOfElements)
    }

    public func readWrapperElements<Element>(offset: Int, numberOfElements: Int) throws -> [Element] where Element: LocatableLayoutWrapper {
        let pointer = ptr + offset
        var currentOffset = offset
        let elements = MemorySequence<Element.Layout>(basePointer: pointer.assumingMemoryBound(to: Element.Layout.self), numberOfElements: numberOfElements).map { (layout: Element.Layout) -> Element in
            let element = Element(layout: layout, offset: currentOffset)
            currentOffset += Element.layoutSize
            return element
        }
        return elements
    }

    public func readString(offset: Int) throws -> String {
        let pointer = ptr + offset
        return .init(cString: pointer.assumingMemoryBound(to: CChar.self))
    }
}

