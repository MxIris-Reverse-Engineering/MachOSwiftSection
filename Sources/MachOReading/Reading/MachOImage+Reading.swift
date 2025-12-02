import MachOKit
import MachOExtensions

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

extension UnsafeRawPointer: Readable {
    public func readElement<Element>(offset: Int) throws -> Element {
        try advanced(by: offset).readElement()
    }
    
    public func readWrapperElement<Element>(offset: Int) throws -> Element where Element : MachOExtensions.LocatableLayoutWrapper {
        try advanced(by: offset).readWrapperElement()
    }
    
    public func readElements<Element>(offset: Int, numberOfElements: Int) throws -> [Element] {
        try advanced(by: offset).readElements(numberOfElements: numberOfElements)
    }
    
    public func readWrapperElements<Element>(offset: Int, numberOfElements: Int) throws -> [Element] where Element : MachOExtensions.LocatableLayoutWrapper {
        try advanced(by: offset).readWrapperElements(numberOfElements: numberOfElements)
    }
    
    public func readString(offset: Int) throws -> String {
        try advanced(by: offset).readString()
    }
    
    package func readElement<Element>() throws -> Element {
        return assumingMemoryBound(to: Element.self).pointee
    }

    package func readWrapperElement<Element>() throws -> Element where Element: LocatableLayoutWrapper {
        let layout: Element.Layout = assumingMemoryBound(to: Element.Layout.self).pointee
        return .init(layout: layout, offset: int)
    }

    package func readElements<Element>(to: Element.Type = Element.self, numberOfElements: Int) throws -> [Element] {
        return MemorySequence<Element>(basePointer: assumingMemoryBound(to: Element.self), numberOfElements: numberOfElements).map { $0 }
    }

    package func readWrapperElements<Element>(to: Element.Type = Element.self, numberOfElements: Int) throws -> [Element] where Element: LocatableLayoutWrapper {
        var currentOffset = int
        let elements = MemorySequence<Element.Layout>(basePointer: assumingMemoryBound(to: Element.Layout.self), numberOfElements: numberOfElements).map { (layout: Element.Layout) -> Element in
            let element = Element(layout: layout, offset: currentOffset)
            currentOffset += Element.layoutSize
            return element
        }
        return elements
    }

    package func readString() throws -> String {
        return .init(cString: assumingMemoryBound(to: CChar.self))
    }
    
    public func resolveOffset(at address: UInt64) -> Int {
        0
    }
    
    public func stripPointerTags(of rawVMAddr: UInt64) -> UInt64 {
        MachOExtensions.stripPointerTags(of: rawVMAddr)
    }
}
