import Foundation
import MachOKit

enum MachOFileHandleError: Error {
    case invalidDataSize
    case invalidLayoutSize
}

struct MachOFileHandleWrapper<Base> {
    let base: Base
    
    init(_ base: Base) {
        self.base = base
    }
}

protocol MachOFileHandle {}

extension MachOFileHandle {
    var machO: MachOFileHandleWrapper<Self> {
        set {}
        get { MachOFileHandleWrapper(self) }
    }

    static var machO: MachOFileHandleWrapper<Self>.Type {
        set {}
        get { MachOFileHandleWrapper.self }
    }
}

extension FileHandle: MachOFileHandle {}

extension MachOFileHandleWrapper where Base: FileHandle {
    func throwIfInvalid(_ isValid: Bool, error: MachOFileHandleError) throws {
        if !isValid {
            throw error
        }
    }
}

extension MachOFileHandleWrapper where Base: FileHandle {
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

extension MachOFileHandleWrapper where Base: FileHandle {
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

extension MachOFileHandleWrapper where Base: FileHandle {
    func readString(
        offset: UInt64,
        size: Int
    ) -> String? {
        let data = readData(
            offset: offset,
            size: size
        )
        return String(cString: data)
    }

    func readString(
        offset: UInt64,
        step: UInt64 = 10
    ) -> String? {
        var data = Data()
        var offset = offset
        while true {
            let new = readData(offset: offset, size: Int(step))
            if new.isEmpty { break }
            data.append(new)
            if new.contains(0) { break }
            offset += UInt64(new.count)
        }

        return String(cString: data)
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
