import Foundation
import MachOKit
import MachOKitExtensions
import FileIO
import AssociatedObject

/// Extends `MachOFile` to conform to `Readable`, enabling file-based reading.
///
/// This extension provides file I/O based reading operations for MachO files.
/// It handles the complexity of:
/// - dyld shared cache support (resolving cross-file references)
/// - Header offset adjustments
/// - File handle management
///
/// ## dyld Shared Cache Support
///
/// When reading from a MachO file that is part of a dyld shared cache,
/// offsets may need to be resolved to different cache files. This extension
/// automatically handles this resolution.
///
/// Only an image read out of a cache asks which cache file an offset lies
/// in. Asked of a standalone file, MachOKit's `cache` used to open the file's
/// path as a dyld cache on every call — the attempt fails and is not
/// remembered — so every read mapped and unmapped the whole file again: two
/// thirds of the time spent reading the iOS 18.5 simulator's SwiftUI.
///
/// ## Example
///
/// ```swift
/// let machOFile: MachOFile = ...
///
/// // Read a raw element
/// let header: mach_header_64 = try machOFile.readElement(offset: 0)
///
/// // Read with wrapper (preserves offset for relative pointer resolution)
/// let descriptor: ProtocolDescriptor = try machOFile.readWrapperElement(offset: offset)
/// ```
extension MachOFile: Readable {
    public func readElement<Element>(
        offset: Int
    ) throws -> Element {
        let originalOffset = offset
        var offset = originalOffset
        var fileIO = fileIO
        if isLoadedFromDyldCache, let cacheAndFileOffset = cacheAndFileOffset(fromStart: offset.cast()) {
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
        if isLoadedFromDyldCache, let cacheAndFileOffset = cacheAndFileOffset(fromStart: offset.cast()) {
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
        if isLoadedFromDyldCache, let cacheAndFileOffset = cacheAndFileOffset(fromStart: offset.cast()) {
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
        if isLoadedFromDyldCache, let cacheAndFileOffset = cacheAndFileOffset(fromStart: offset.cast()) {
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
        if isLoadedFromDyldCache, let cacheAndFileOffset = cacheAndFileOffset(fromStart: offset.cast()) {
            offset = cacheAndFileOffset.1.cast()
            fileIO = cacheAndFileOffset.0.fileIO
        }
        return fileIO.machO.readString(offset: numericCast(offset + headerStartOffset))
    }
}
