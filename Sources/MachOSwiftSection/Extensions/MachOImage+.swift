import Foundation
@_spi(Support) import MachOKit

extension MachOImage {
    func findSwiftSection64(for section: SwiftMachOSection) -> Section64? {
        findSwiftSection64(for: section.rawValue)
    }

    func findSwiftSection32(for section: SwiftMachOSection) -> Section? {
        findSwiftSection32(for: section.rawValue)
    }

    // [dyld implementation](https://github.com/apple-oss-distributions/dyld/blob/66c652a1f1f6b7b5266b8bbfd51cb0965d67cc44/common/MachOFile.cpp#L3880)
    func findSwiftSection64(for name: String) -> Section64? {
        let segmentNames = [
            "__DATA", "__DATA_CONST", "__DATA_DIRTY"
        ]
        let segments = segments64
        for segment in segments {
            guard segmentNames.contains(segment.segmentName) else {
                continue
            }
            if let section = segment._section(for: name, in: self) {
                return section
            }
        }
        return nil
    }

    func findSwiftSection32(for name: String) -> Section? {
        let segmentNames = [
            "__DATA", "__DATA_CONST", "__DATA_DIRTY"
        ]
        let segments = segments32
        for segment in segments {
            guard segmentNames.contains(segment.segmentName) else {
                continue
            }
            if let section = segment._section(for: name, in: self) {
                return section
            }
        }
        return nil
    }
}

extension MachOImage {
    func assumingElement<Element>(
        offset: Int
    ) throws -> Element {
        let pointer = ptr + offset
        return pointer.assumingMemoryBound(to: Element.self).pointee
    }

    func assumingElement<Element>(
        offset: Int
    ) throws -> Element where Element: LocatableLayoutWrapper {
        let pointer = ptr + offset
        let layout: Element.Layout = pointer.assumingMemoryBound(to: Element.Layout.self).pointee
        return .init(layout: layout, offset: offset)
    }

    func assumingElements<Element>(
        offset: Int,
        numberOfElements: Int
    ) throws -> [Element] {
        let pointer = ptr + offset
        return MemorySequence<Element>(basePointer: pointer.assumingMemoryBound(to: Element.self), numberOfElements: numberOfElements).map { $0 }
    }
    
    func assumingElements<Element>(
        offset: Int,
        numberOfElements: Int
    ) throws -> [Element] where Element: LocatableLayoutWrapper {
        let pointer = ptr + offset
        var currentOffset = offset
        let elements = MemorySequence<Element.Layout>(basePointer: pointer.assumingMemoryBound(to: Element.Layout.self), numberOfElements: numberOfElements).map { (layout: Element.Layout) -> Element in
            let element = Element(layout: layout, offset: currentOffset)
            currentOffset += Element.layoutSize
            return element
        }
        return elements
    }

    func assumingString(offset: Int) throws -> String {
        let pointer = ptr + offset
        return .init(cString: pointer.assumingMemoryBound(to: CChar.self))
    }
}

extension UnsafeRawPointer {
    var uint: UInt {
        UInt(bitPattern: self)
    }
    
    var int: Int {
        Int(bitPattern: self)
    }
}
