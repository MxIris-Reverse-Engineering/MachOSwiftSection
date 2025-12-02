import Foundation
import MachOKit
import MachOExtensions
import FileIO
import AssociatedObject

extension MachOFile {
    @AssociatedObject(.retain(.nonatomic))
    private var _fileHandle: FileHandle?

    var fileHandle: FileHandle {
        if let _fileHandle {
            return _fileHandle
        } else {
            let fileHandle = try! FileHandle(forReadingFrom: url)
            _fileHandle = fileHandle
            return fileHandle
        }
    }

    @AssociatedObject(.retain(.nonatomic))
    private var _fileIO: MemoryMappedFile?

    var fileIO: MemoryMappedFile {
        if let _fileIO {
            return _fileIO
        } else {
            let fileIO = try! MemoryMappedFile.open(url: url, isWritable: false)
            _fileIO = fileIO
            return fileIO
        }
    }
}

extension MachOFile: Readable {
    public func readElement<Element>(
        offset: Int
    ) throws -> Element {
        let originalOffset = offset
        var offset = originalOffset
        var fileIO = fileIO
        if let cacheAndFileOffset = cacheAndFileOffset(fromStart: offset.cast()) {
            offset = cacheAndFileOffset.1.cast()
            fileIO = cacheAndFileOffset.0.fileIO
        }
        return try fileIO.machO.read(offset: numericCast(offset + headerStartOffset))
    }

    public func readElement<Element>(
        offset: Int
    ) throws -> Element where Element: LocatableLayoutWrapper {
        return try readWrapperElement(offset: offset)
    }

    public func readWrapperElement<Element>(offset: Int) throws -> Element where Element: LocatableLayoutWrapper {
        let originalOffset = offset
        var offset = originalOffset
        var fileIO = fileIO
        if let cacheAndFileOffset = cacheAndFileOffset(fromStart: offset.cast()) {
            offset = cacheAndFileOffset.1.cast()
            fileIO = cacheAndFileOffset.0.fileIO
        }
        let layout: Element.Layout = try fileIO.machO.read(offset: numericCast(offset + headerStartOffset))
        return .init(layout: layout, offset: originalOffset)
    }

    public func readElements<Element>(
        offset: Int,
        numberOfElements: Int
    ) throws -> [Element] {
        let originalOffset = offset
        var offset = originalOffset
        var fileIO = fileIO
        if let cacheAndFileOffset = cacheAndFileOffset(fromStart: offset.cast()) {
            offset = cacheAndFileOffset.1.cast()
            fileIO = cacheAndFileOffset.0.fileIO
        }
        var currentOffset = offset
        let elements = try fileIO.machO.readDataSequence(offset: numericCast(offset + headerStartOffset), numberOfElements: numberOfElements).map { (element: Element) -> Element in
            currentOffset += MemoryLayout<Element>.size
            return element
        }
        return elements
    }

    public func readElements<Element>(
        offset: Int,
        numberOfElements: Int
    ) throws -> [Element] where Element: LocatableLayoutWrapper {
        return try readWrapperElements(offset: offset, numberOfElements: numberOfElements)
    }

    public func readWrapperElements<Element>(offset: Int, numberOfElements: Int) throws -> [Element] where Element: LocatableLayoutWrapper {
        let originalOffset = offset
        var offset = originalOffset
        var fileIO = fileIO
        if let cacheAndFileOffset = cacheAndFileOffset(fromStart: offset.cast()) {
            offset = cacheAndFileOffset.1.cast()
            fileIO = cacheAndFileOffset.0.fileIO
        }
        var currentOffset = originalOffset
        let elements = try fileIO.machO.readDataSequence(offset: numericCast(offset + headerStartOffset), numberOfElements: numberOfElements).map { (layout: Element.Layout) -> Element in
            let element = Element(layout: layout, offset: currentOffset)
            currentOffset += Element.layoutSize
            return element
        }
        return elements
    }

    public func readString(offset: Int) throws -> String {
        let originalOffset = offset
        var offset = originalOffset
        var fileIO = fileIO
        if let cacheAndFileOffset = cacheAndFileOffset(fromStart: offset.cast()) {
            offset = cacheAndFileOffset.1.cast()
            fileIO = cacheAndFileOffset.0.fileIO
        }
        return fileIO.machO.readString(offset: numericCast(offset + headerStartOffset))
    }
}
