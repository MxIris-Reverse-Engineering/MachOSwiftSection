import Foundation
@_spi(Support) import MachOKit
import MachOKitExtensions
import FileIO

/// Extends `MachOFile` to conform to `Readable`, enabling file-based reading.
///
/// This extension provides file I/O based reading operations for MachO files.
/// It handles the complexity of:
/// - dyld shared cache support (resolving cross-file references)
/// - Header offset adjustments
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
/// ## The bytes read
///
/// Every value is read straight out of the mapping MachOKit made when it
/// opened the file (`fileBytes`), shared by every value assembled from that
/// opening: no second mapping of the file, and no `Data` allocated and
/// copied per read (evolution proposal `machofile-performance`). A read
/// outside the file throws.
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
        try withFileBytes(atOffset: offset, count: MemoryLayout<Element>.size) { bytes in
            bytes.loadUnaligned(as: Element.self)
        }
    }

    public func readElement<Element>(
        offset: Int
    ) throws -> Element where Element: LocatableLayoutWrapper {
        return try readWrapperElement(offset: offset)
    }

    public func readWrapperElement<Element>(offset: Int) throws -> Element where Element: LocatableLayoutWrapper {
        let layout: Element.Layout = try withFileBytes(atOffset: offset, count: MemoryLayout<Element.Layout>.size) { bytes in
            bytes.loadUnaligned(as: Element.Layout.self)
        }
        return .init(layout: layout, offset: offset)
    }

    public func readElements<Element>(
        offset: Int,
        numberOfElements: Int
    ) throws -> [Element] {
        let elementSize = MemoryLayout<Element>.size
        return try withFileBytes(atOffset: offset, count: elementSize * numberOfElements) { bytes in
            (0 ..< numberOfElements).map { index in
                bytes.loadUnaligned(fromByteOffset: index * elementSize, as: Element.self)
            }
        }
    }

    public func readElements<Element>(
        offset: Int,
        numberOfElements: Int
    ) throws -> [Element] where Element: LocatableLayoutWrapper {
        return try readWrapperElements(offset: offset, numberOfElements: numberOfElements)
    }

    public func readWrapperElements<Element>(offset: Int, numberOfElements: Int) throws -> [Element] where Element: LocatableLayoutWrapper {
        let layoutSize = MemoryLayout<Element.Layout>.size
        return try withFileBytes(atOffset: offset, count: layoutSize * numberOfElements) { bytes in
            (0 ..< numberOfElements).map { index in
                Element(
                    layout: bytes.loadUnaligned(fromByteOffset: index * layoutSize, as: Element.Layout.self),
                    offset: offset + index * Element.layoutSize
                )
            }
        }
    }

    public func readString(offset: Int) throws -> String {
        try withFileBytes(fromOffset: offset) { bytes in
            guard let start = bytes.baseAddress else { return "" }
            // Up to the terminator, which a string table always carries; a
            // run without one ends at the end of the file.
            guard memchr(start, 0, bytes.count) != nil else {
                return String(decoding: bytes, as: UTF8.self)
            }
            return String(cString: start.assumingMemoryBound(to: CChar.self))
        }
    }
}

extension MachOFile {
    /// Runs `body` over the `count` bytes at `offset`, read out of the file
    /// that holds them: this file, or — for an image of a dyld cache — the
    /// cache file the offset lies in. Throws when they lie outside it.
    @inline(__always)
    fileprivate func withFileBytes<Result>(
        atOffset offset: Int,
        count: Int,
        _ body: (UnsafeRawBufferPointer) throws -> Result
    ) throws -> Result {
        try withContainingFileBytes(atOffset: offset) { fileBytes, fileOffset in
            guard count >= 0, fileOffset <= fileBytes.count, count <= fileBytes.count - fileOffset, let base = fileBytes.baseAddress else {
                throw FileIOError.offsetOutOfBounds
            }
            return try body(UnsafeRawBufferPointer(start: base + fileOffset, count: count))
        }
    }

    /// Runs `body` over the bytes from `offset` to the end of the file that
    /// holds them.
    @inline(__always)
    fileprivate func withFileBytes<Result>(
        fromOffset offset: Int,
        _ body: (UnsafeRawBufferPointer) throws -> Result
    ) throws -> Result {
        try withContainingFileBytes(atOffset: offset) { fileBytes, fileOffset in
            guard fileOffset <= fileBytes.count, let base = fileBytes.baseAddress else {
                throw FileIOError.offsetOutOfBounds
            }
            return try body(UnsafeRawBufferPointer(start: base + fileOffset, count: fileBytes.count - fileOffset))
        }
    }

    /// The bytes of the file `offset` lies in and the offset within them.
    @inline(__always)
    private func withContainingFileBytes<Result>(
        atOffset offset: Int,
        _ body: (UnsafeRawBufferPointer, Int) throws -> Result
    ) throws -> Result {
        if isLoadedFromDyldCache, let (cache, fileOffset) = cacheAndFileOffset(fromStart: offset.cast()) {
            // The cache file's bytes are valid while a value sharing its
            // handle lives; this one may be the only such value.
            return try withExtendedLifetime(cache) {
                let position = Int(fileOffset) + headerStartOffset
                guard position >= 0 else { throw FileIOError.offsetOutOfBounds }
                return try body(cache.fileBytes, position)
            }
        }
        let position = offset + headerStartOffset
        guard position >= 0 else { throw FileIOError.offsetOutOfBounds }
        return try body(fileBytes, position)
    }
}
