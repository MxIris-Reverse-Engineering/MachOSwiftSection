import Foundation
import FileIO
import MachOKit
import MachOExtensions

extension MemoryMappedFile: MachONamespacing {}

extension MachONamespace where Base: _FileIOProtocol {
    package func readDataSequence<Element>(
        offset: UInt64,
        numberOfElements: Int,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> DataSequence<Element> where Element: LayoutWrapper {
        let size = Element.layoutSize * numberOfElements
        var data = try base.readData(
            offset: numericCast(offset),
            length: size
        )

        try throwIfInvalid(Element.layoutSize == MemoryLayout<Element>.size, error: .invalidLayoutSize)

        try throwIfInvalid(data.count >= size, error: .invalidDataSize)

        if let swapHandler { swapHandler(&data) }
        return .init(
            data: data,
            numberOfElements: numberOfElements
        )
    }

    @_disfavoredOverload
    package func readDataSequence<Element>(
        offset: UInt64,
        numberOfElements: Int,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> DataSequence<Element> {
        let size = MemoryLayout<Element>.size * numberOfElements
        var data = try base.readData(
            offset: numericCast(offset),
            length: size
        )

        try throwIfInvalid(data.count >= size, error: .invalidDataSize)
        if let swapHandler { swapHandler(&data) }
        return .init(
            data: data,
            numberOfElements: numberOfElements
        )
    }

    package func readDataSequence<Element>(
        offset: UInt64,
        entrySize: Int,
        numberOfElements: Int,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> DataSequence<Element> where Element: LayoutWrapper {
        let size = entrySize * numberOfElements
        var data = try base.readData(
            offset: numericCast(offset),
            length: size
        )

        try throwIfInvalid(Element.layoutSize == MemoryLayout<Element>.size, error: .invalidLayoutSize)

        try throwIfInvalid(data.count >= size, error: .invalidDataSize)

        if let swapHandler { swapHandler(&data) }
        return .init(
            data: data,
            entrySize: entrySize
        )
    }

    @_disfavoredOverload
    package func readDataSequence<Element>(
        offset: UInt64,
        entrySize: Int,
        numberOfElements: Int,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> DataSequence<Element> {
        let size = entrySize * numberOfElements
        var data = try base.readData(
            offset: numericCast(offset),
            length: size
        )

        try throwIfInvalid(data.count >= size, error: .invalidDataSize)

        if let swapHandler { swapHandler(&data) }
        return .init(
            data: data,
            entrySize: entrySize
        )
    }
}

extension MachONamespace where Base: _FileIOProtocol {
    package func read<Element>(
        offset: UInt64,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> Element? where Element: LayoutWrapper {
        var data = try base.readData(
            offset: numericCast(offset),
            length: Element.layoutSize
        )

        try throwIfInvalid(Element.layoutSize == MemoryLayout<Element>.size, error: .invalidLayoutSize)
        try throwIfInvalid(data.count >= Element.layoutSize, error: .invalidDataSize)

        if let swapHandler { swapHandler(&data) }
        return data.withUnsafeBytes {
            $0.load(as: Element.self)
        }
    }

    package func read<Element>(
        offset: UInt64,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> Element? {
        var data = try base.readData(
            offset: numericCast(offset),
            length: MemoryLayout<Element>.size
        )
        try throwIfInvalid(data.count >= MemoryLayout<Element>.size, error: .invalidDataSize)
        if let swapHandler { swapHandler(&data) }
        return data.withUnsafeBytes {
            $0.load(as: Element.self)
        }
    }

    package func read<Element>(
        offset: UInt64,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> Element where Element: LayoutWrapper {
        var data = try base.readData(
            offset: numericCast(offset),
            length: Element.layoutSize
        )
        try throwIfInvalid(Element.layoutSize == MemoryLayout<Element>.size, error: .invalidLayoutSize)
        try throwIfInvalid(data.count >= Element.layoutSize, error: .invalidDataSize)
        if let swapHandler { swapHandler(&data) }
        return data.withUnsafeBytes {
            $0.load(as: Element.self)
        }
    }

    package func read<Element>(
        offset: UInt64,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> Element {
        var data = try base.readData(
            offset: numericCast(offset),
            length: MemoryLayout<Element>.size
        )
        try throwIfInvalid(data.count >= MemoryLayout<Element>.size, error: .invalidDataSize)
        if let swapHandler { swapHandler(&data) }
        return data.withUnsafeBytes {
            $0.load(as: Element.self)
        }
    }
}

extension MachONamespace where Base: _FileIOProtocol {
    @_disfavoredOverload
    @inline(__always)
    package func readString(
        offset: UInt64,
        size: Int
    ) -> String? {
        let data = try! base.readData(
            offset: numericCast(offset),
            length: size
        )
        return String(cString: data)
    }

    @_disfavoredOverload
    @inline(__always)
    package func readString(
        offset: UInt64,
        step: Int = 10
    ) -> String? {
        var data = Data()
        var offset = offset
        while true {
            guard let new = try? base.readData(
                offset: numericCast(offset),
                upToCount: step
            ) else { break }
            if new.isEmpty { break }
            data.append(new)
            if new.contains(0) { break }
            offset += UInt64(new.count)
        }

        return String(cString: data)
    }
}

extension MachONamespace where Base == MemoryMappedFile {
    @inline(__always)
    package func readString(
        offset: UInt64
    ) -> String {
        String(
            cString: base.ptr
                .advanced(by: numericCast(offset))
                .assumingMemoryBound(to: CChar.self)
        )
    }

    @inline(__always)
    package func readString(
        offset: UInt64,
        size: Int // ignored
    ) -> String {
        readString(offset: offset)
    }

    @inline(__always)
    package func readString(
        offset: UInt64,
        step: Int = 10 // ignored
    ) -> String {
        readString(offset: offset)
    }
}
