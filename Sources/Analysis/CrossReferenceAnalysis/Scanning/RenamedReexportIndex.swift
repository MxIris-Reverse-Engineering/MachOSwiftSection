import Foundation
import MachOKit

/// A symbol one image re-exports under a name of its own.
struct RenamedReexport: Hashable {
    /// The re-exporting image.
    let imageIndex: Int
    /// The name it exports the symbol under.
    let name: String
}

/// Every symbol an image re-exports under another name, by the image it
/// re-exports from and the symbol's name there.
///
/// An image calling such a function imports it by the re-exporting image's
/// name: libsystem_c exports libsystem_platform's `__platform_strlen` as
/// `_strlen`, CoreGraphics exports SkyLight's `_SLBeginDisplayConfiguration`
/// as `_CGBeginDisplayConfiguration`, and every caller imports the latter. A
/// prefilter by imports has to look for those names too. The macOS 27.2 cache
/// holds 1,438 such re-exports in 12 images, 1,112 of them CoreGraphics'.
///
/// Read from every image's export trie, once; only the renamed re-exports
/// are kept.
struct RenamedReexportIndex {
    /// By the image re-exported from, then by the symbol's name there.
    let reexportsByProvider: [Int: [String: [RenamedReexport]]]

    init(analyzer: CrossReferenceAnalyzer) {
        let images = analyzer.images
        let entriesByImage = UnsafeMutableBufferPointer<[TrieEntry]>.allocate(capacity: images.count)
        entriesByImage.initialize(repeating: [])
        defer {
            _ = entriesByImage.deinitialize()
            entriesByImage.deallocate()
        }
        nonisolated(unsafe) let entries = entriesByImage.baseAddress!
        DispatchQueue.concurrentPerform(iterations: images.count) { imageIndex in
            guard let trie = images[imageIndex].exportTrie, trie.exportSize > 0 else { return }
            (entries + imageIndex).pointee = Self.renamedReexports(inTrieAt: trie.basePointer.assumingMemoryBound(to: UInt8.self), size: trie.exportSize)
        }
        var reexportsByProvider: [Int: [String: [RenamedReexport]]] = [:]
        for imageIndex in images.indices where !entriesByImage[imageIndex].isEmpty {
            // An entry names the image it re-exports from by its ordinal
            // among the image's dylib load commands, from 1.
            let dependencies = analyzer.dependencyImageIndices(ofImageAt: imageIndex)
            for entry in entriesByImage[imageIndex] {
                guard entry.ordinal >= 1, entry.ordinal <= UInt64(dependencies.count) else { continue }
                let reexport = RenamedReexport(imageIndex: imageIndex, name: entry.name)
                for provider in dependencies[Int(entry.ordinal) - 1] {
                    reexportsByProvider[provider, default: [:]][entry.importedName, default: []].append(reexport)
                }
            }
        }
        self.reexportsByProvider = reexportsByProvider
    }

    struct TrieEntry {
        let name: String
        let ordinal: UInt64
        let importedName: String
    }

    /// `EXPORT_SYMBOL_FLAGS_REEXPORT`.
    private static let reexportFlag: UInt64 = 0x08

    /// The renamed re-exports among the entries of the export trie at
    /// `base`: walks every node, and spells out the names of those alone.
    static func renamedReexports(inTrieAt base: UnsafePointer<UInt8>, size: Int) -> [TrieEntry] {
        var result: [TrieEntry] = []
        var name: [UInt8] = []
        // A node still to visit, with how long its parent's name is and the
        // edge label that leads to it.
        var pending: [(offset: Int, parentNameLength: Int, labelStart: Int, labelLength: Int)] = [(0, 0, 0, 0)]
        // A well-formed trie has fewer nodes than bytes; a malformed one may
        // loop.
        var remainingNodes = size
        while let node = pending.popLast(), remainingNodes > 0 {
            remainingNodes -= 1
            name.removeLast(name.count - node.parentNameLength)
            name.append(contentsOf: UnsafeBufferPointer(start: base + node.labelStart, count: node.labelLength))
            var cursor = node.offset
            guard let terminalSize = readULEB128(base, size: size, at: &cursor) else { continue }
            let childrenOffset = cursor + Int(clamping: terminalSize)
            if terminalSize > 0,
               let flags = readULEB128(base, size: size, at: &cursor), flags & reexportFlag != 0,
               let ordinal = readULEB128(base, size: size, at: &cursor),
               let importedName = readCString(base, size: size, at: cursor),
               !importedName.isEmpty {
                let exportedName = String(decoding: name, as: UTF8.self)
                if importedName != exportedName {
                    result.append(TrieEntry(name: exportedName, ordinal: ordinal, importedName: importedName))
                }
            }
            guard childrenOffset < size else { continue }
            cursor = childrenOffset
            let childCount = Int(base[cursor])
            cursor += 1
            for _ in 0 ..< childCount {
                let labelStart = cursor
                while cursor < size, base[cursor] != 0 { cursor += 1 }
                guard cursor < size else { break }
                let labelLength = cursor - labelStart
                cursor += 1
                guard let childOffset = readULEB128(base, size: size, at: &cursor), childOffset < UInt64(size) else { break }
                pending.append((Int(childOffset), name.count, labelStart, labelLength))
            }
        }
        return result
    }

    private static func readULEB128(_ base: UnsafePointer<UInt8>, size: Int, at cursor: inout Int) -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while cursor < size, shift < 64 {
            let byte = base[cursor]
            cursor += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        return nil
    }

    private static func readCString(_ base: UnsafePointer<UInt8>, size: Int, at offset: Int) -> String? {
        var end = offset
        while end < size, base[end] != 0 { end += 1 }
        guard end < size else { return nil }
        return String(decoding: UnsafeBufferPointer(start: base + offset, count: end - offset), as: UTF8.self)
    }
}
