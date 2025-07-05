import MachOKit
import MachOExtensions

extension MachOImage: MachOReadable {
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

    public func readWrapperElement<Element>(offset: Int) throws -> Element where Element : LocatableLayoutWrapper {
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

    public func readWrapperElements<Element>(offset: Int, numberOfElements: Int) throws -> [Element] where Element : LocatableLayoutWrapper {
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
