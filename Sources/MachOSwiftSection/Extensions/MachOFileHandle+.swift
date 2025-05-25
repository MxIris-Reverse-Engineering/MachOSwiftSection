import Foundation
import MachOKit
import FileIO

enum MachOFileHandleError: Error {
    case invalidDataSize
    case invalidLayoutSize
}

struct MachOFileHandle<Base> {
    let base: Base

    init(_ base: Base) {
        self.base = base
    }
}

protocol MachOFileHandleConvertable {}

extension MachOFileHandleConvertable {
    var machO: MachOFileHandle<Self> {
        set {}
        get { MachOFileHandle(self) }
    }

    static var machO: MachOFileHandle<Self>.Type {
        set {}
        get { MachOFileHandle.self }
    }
}

extension FileHandle: MachOFileHandleConvertable {}
extension MemoryMappedFile: MachOFileHandleConvertable {}

extension MachOFileHandle {
    func throwIfInvalid(_ isValid: Bool, error: MachOFileHandleError) throws {
        if !isValid {
            throw error
        }
    }
}

extension MachOFileHandle where Base: FileHandle {
    func readDataSequence<Element>(
        offset: UInt64,
        numberOfElements: Int,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> DataSequence<Element> where Element: LayoutWrapper {
        base.seek(toFileOffset: offset)
        let size = Element.layoutSize * numberOfElements
        var data = base.readData(
            ofLength: size
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
    func readDataSequence<Element>(
        offset: UInt64,
        numberOfElements: Int,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> DataSequence<Element> {
        base.seek(toFileOffset: offset)
        let size = MemoryLayout<Element>.size * numberOfElements
        var data = base.readData(
            ofLength: size
        )

        try throwIfInvalid(data.count >= size, error: .invalidDataSize)
        if let swapHandler { swapHandler(&data) }
        return .init(
            data: data,
            numberOfElements: numberOfElements
        )
    }

    func readDataSequence<Element>(
        offset: UInt64,
        entrySize: Int,
        numberOfElements: Int,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> DataSequence<Element> where Element: LayoutWrapper {
        base.seek(toFileOffset: offset)
        let size = entrySize * numberOfElements
        var data = base.readData(
            ofLength: size
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
    func readDataSequence<Element>(
        offset: UInt64,
        entrySize: Int,
        numberOfElements: Int,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> DataSequence<Element> {
        base.seek(toFileOffset: offset)
        let size = entrySize * numberOfElements
        var data = base.readData(
            ofLength: size
        )

        try throwIfInvalid(data.count >= size, error: .invalidDataSize)

        if let swapHandler { swapHandler(&data) }
        return .init(
            data: data,
            entrySize: entrySize
        )
    }
}

extension MachOFileHandle where Base: FileHandle {
    func read<Element>(
        offset: UInt64,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> Element? where Element: LayoutWrapper {
        base.seek(toFileOffset: offset)
        var data = base.readData(
            ofLength: Element.layoutSize
        )

        try throwIfInvalid(Element.layoutSize == MemoryLayout<Element>.size, error: .invalidLayoutSize)
        try throwIfInvalid(data.count >= Element.layoutSize, error: .invalidDataSize)

        if let swapHandler { swapHandler(&data) }
        return data.withUnsafeBytes {
            $0.load(as: Element.self)
        }
    }

    func read<Element>(
        offset: UInt64,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> Element? {
        base.seek(toFileOffset: offset)
        var data = base.readData(
            ofLength: MemoryLayout<Element>.size
        )
        try throwIfInvalid(data.count >= MemoryLayout<Element>.size, error: .invalidDataSize)
        if let swapHandler { swapHandler(&data) }
        return data.withUnsafeBytes {
            $0.load(as: Element.self)
        }
    }

    func read<Element>(
        offset: UInt64,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> Element where Element: LayoutWrapper {
        base.seek(toFileOffset: offset)
        var data = base.readData(
            ofLength: Element.layoutSize
        )
        try throwIfInvalid(Element.layoutSize == MemoryLayout<Element>.size, error: .invalidLayoutSize)
        try throwIfInvalid(data.count >= Element.layoutSize, error: .invalidDataSize)
        if let swapHandler { swapHandler(&data) }
        return data.withUnsafeBytes {
            $0.load(as: Element.self)
        }
    }

    func read<Element>(
        offset: UInt64,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> Element {
        base.seek(toFileOffset: offset)
        var data = base.readData(
            ofLength: MemoryLayout<Element>.size
        )
        try throwIfInvalid(data.count >= MemoryLayout<Element>.size, error: .invalidDataSize)
        if let swapHandler { swapHandler(&data) }
        return data.withUnsafeBytes {
            $0.load(as: Element.self)
        }
    }
}

extension MachOFileHandle where Base: FileHandle {
    func readString(
        offset: UInt64,
        size: Int
    ) -> String {
        let data = readData(
            offset: offset,
            size: size
        )
        return String(cString: data) ?? ""
    }

    func readString(
        offset: UInt64,
        step: UInt64 = 10
    ) -> String {
        var data = Data()
        var offset = offset
        while true {
            let new = readData(offset: offset, size: Int(step))
            if new.isEmpty { break }
            data.append(new)
            if new.contains(0) { break }
            offset += UInt64(new.count)
        }

        return String(cString: data) ?? ""
    }

    func readData(
        offset: UInt64,
        size: Int
    ) -> Data {
        base.seek(toFileOffset: offset)
        return base.readData(
            ofLength: size
        )
    }
}

extension MachOFileHandle where Base: _FileIOProtocol {
    func readDataSequence<Element>(
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
    func readDataSequence<Element>(
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

    func readDataSequence<Element>(
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
    func readDataSequence<Element>(
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

extension MachOFileHandle where Base: _FileIOProtocol {
    func read<Element>(
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

    func read<Element>(
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

    func read<Element>(
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

    func read<Element>(
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

extension MachOFileHandle where Base: _FileIOProtocol {
    @_disfavoredOverload
    @inlinable @inline(__always)
    func readString(
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
    @inlinable @inline(__always)
    func readString(
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

extension MachOFileHandle where Base == MemoryMappedFile {
    @inlinable @inline(__always)
    func readString(
        offset: UInt64
    ) -> String {
        String(
            cString: base.ptr
                .advanced(by: numericCast(offset))
                .assumingMemoryBound(to: CChar.self)
        )
    }

    @inlinable @inline(__always)
    func readString(
        offset: UInt64,
        size: Int // ignored
    ) -> String {
        readString(offset: offset)
    }

    @inlinable @inline(__always)
    func readString(
        offset: UInt64,
        step: Int = 10 // ignored
    ) -> String {
        readString(offset: offset)
    }
}
