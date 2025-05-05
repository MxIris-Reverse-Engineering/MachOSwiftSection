import Foundation
@_spi(Support) import MachOKit

@_spi(Support)
public enum MachOFileHandleError: Error {
    case invalidDataSize
    case invalidLayoutSize
}

extension FileHandle {
    func throwIfInvalid(_ isValid: Bool, error: MachOFileHandleError) throws {
        if !isValid {
            throw error
        }
    }
}

extension FileHandle {
    @_spi(Support)
    public func readDataSequence<Element>(
        offset: UInt64,
        numberOfElements: Int,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> DataSequence<Element> where Element: LayoutWrapper {
        seek(toFileOffset: offset)
        let size = Element.layoutSize * numberOfElements
        var data = readData(
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

    @_spi(Support)
    @_disfavoredOverload
    public func readDataSequence<Element>(
        offset: UInt64,
        numberOfElements: Int,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> DataSequence<Element> {
        seek(toFileOffset: offset)
        let size = MemoryLayout<Element>.size * numberOfElements
        var data = readData(
            ofLength: size
        )
        
        try throwIfInvalid(data.count >= size, error: .invalidDataSize)
        if let swapHandler { swapHandler(&data) }
        return .init(
            data: data,
            numberOfElements: numberOfElements
        )
    }

    @_spi(Support)
    public func readDataSequence<Element>(
        offset: UInt64,
        entrySize: Int,
        numberOfElements: Int,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> DataSequence<Element> where Element: LayoutWrapper {
        seek(toFileOffset: offset)
        let size = entrySize * numberOfElements
        var data = readData(
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

    @_spi(Support)
    @_disfavoredOverload
    public func readDataSequence<Element>(
        offset: UInt64,
        entrySize: Int,
        numberOfElements: Int,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> DataSequence<Element> {
        seek(toFileOffset: offset)
        let size = entrySize * numberOfElements
        var data = readData(
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

extension FileHandle {
    @_spi(Support)
    public func read<Element>(
        offset: UInt64,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> Optional<Element> where Element: LayoutWrapper {
        seek(toFileOffset: offset)
        var data = readData(
            ofLength: Element.layoutSize
        )
        
        try throwIfInvalid(Element.layoutSize == MemoryLayout<Element>.size, error: .invalidLayoutSize)
        try throwIfInvalid(data.count >= Element.layoutSize, error: .invalidDataSize)
        
        if let swapHandler { swapHandler(&data) }
        return data.withUnsafeBytes {
            $0.load(as: Element.self)
        }
    }

    @_spi(Support)
    public func read<Element>(
        offset: UInt64,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> Optional<Element> {
        seek(toFileOffset: offset)
        var data = readData(
            ofLength: MemoryLayout<Element>.size
        )
        try throwIfInvalid(data.count >= MemoryLayout<Element>.size, error: .invalidDataSize)
        if let swapHandler { swapHandler(&data) }
        return data.withUnsafeBytes {
            $0.load(as: Element.self)
        }
    }

    @_spi(Support)
    public func read<Element>(
        offset: UInt64,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> Element where Element: LayoutWrapper {
        seek(toFileOffset: offset)
        var data = readData(
            ofLength: Element.layoutSize
        )
        try throwIfInvalid(Element.layoutSize == MemoryLayout<Element>.size, error: .invalidLayoutSize)
        try throwIfInvalid(data.count >= Element.layoutSize, error: .invalidDataSize)
        if let swapHandler { swapHandler(&data) }
        return data.withUnsafeBytes {
            $0.load(as: Element.self)
        }
    }

    @_spi(Support)
    public func read<Element>(
        offset: UInt64,
        swapHandler: ((inout Data) -> Void)? = nil
    ) throws -> Element {
        seek(toFileOffset: offset)
        var data = readData(
            ofLength: MemoryLayout<Element>.size
        )
        try throwIfInvalid(data.count >= MemoryLayout<Element>.size, error: .invalidDataSize)
        if let swapHandler { swapHandler(&data) }
        return data.withUnsafeBytes {
            $0.load(as: Element.self)
        }
    }
}

extension FileHandle {
    @_spi(Support)
    public func readString(
        offset: UInt64,
        size: Int
    ) -> String? {
        let data = readData(
            offset: offset,
            size: size
        )
        return String(cString: data)
    }

    @_spi(Support)
    public func readString(
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

    @_spi(Support)
    public func readData(
        offset: UInt64,
        size: Int
    ) -> Data {
        seek(toFileOffset: offset)
        return readData(
            ofLength: size
        )
    }
}
