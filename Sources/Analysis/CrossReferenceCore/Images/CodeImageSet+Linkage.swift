import Foundation
import MachOKit

/// Which images link which: what tells the images that can bind to another
/// image's symbols when they keep no undefined symbol for them.
///
/// Only 245 of the macOS 27.2 shared cache's 4,113 images keep any Swift
/// symbol among their undefined symbols. The rest bind Swift symbols with
/// nothing left to show: SharedWithYou keeps 314 undefined symbols, all C
/// functions and Objective-C classes, yet calls `URL`'s metadata accessor
/// through a GOT stub the cache builder bound; 44 images import `URL.path`
/// by name, and many more call it. A Swift symbol another image uses is told
/// by the linkage instead: an image binds only to the images it links and
/// the ones those re-export.
package struct Linkage {
    /// The images that link each image.
    package let dependents: [Int: [Int]]
    /// The images that re-export each image.
    package let reexporters: [Int: [Int]]
}

extension CodeImageSet {
    /// The images among `candidates` that can bind to the symbols of the
    /// image at `imageIndex`: the image itself, the images re-exporting it —
    /// SwiftUI re-exports SwiftUICore — and every image linking one of those.
    package func imageIndices(linkingImageAt imageIndex: Int, among candidates: some Sequence<Int>) -> [Int] {
        let linkage = self.linkage()
        let providers = Self.providers(of: imageIndex, in: linkage)
        var linkers = providers
        for provider in providers {
            linkers.formUnion(linkage.dependents[provider] ?? [])
        }
        return candidates.filter(linkers.contains)
    }

    /// The image at `imageIndex` and every image re-exporting it, directly or
    /// through another re-exporter: the images its symbols can be bound
    /// through under their own names.
    private static func providers(of imageIndex: Int, in linkage: Linkage) -> Set<Int> {
        var providers: Set<Int> = [imageIndex]
        var pending = [imageIndex]
        while let provider = pending.popLast() {
            for reexporter in linkage.reexporters[provider] ?? [] where providers.insert(reexporter).inserted {
                pending.append(reexporter)
            }
        }
        return providers
    }

    /// The names other images re-export the symbols `symbolNames` of the
    /// image at `imageIndex` under, which is what the callers of those
    /// symbols import: `_strlen`, `_index` … for libsystem_platform's
    /// `__platform_strlen`, `_CGBeginDisplayConfiguration` for SkyLight's
    /// `_SLBeginDisplayConfiguration`.
    ///
    /// Follows a re-export renamed again, and one made through an image that
    /// re-exports this one whole. The first call walks every image's export
    /// trie.
    package func reexportedNames(ofSymbolsNamed symbolNames: [String], inImageAt imageIndex: Int) -> [String] {
        let index = renamedReexports()
        let linkage = self.linkage()
        var names: [String] = []
        var visited = Set<RenamedReexport>()
        var pending = symbolNames.map { RenamedReexport(imageIndex: imageIndex, name: $0) }
        while let symbol = pending.popLast() {
            guard visited.insert(symbol).inserted else { continue }
            for provider in Self.providers(of: symbol.imageIndex, in: linkage) {
                for reexport in index.reexportsByProvider[provider]?[symbol.name] ?? [] {
                    if !symbolNames.contains(reexport.name), !names.contains(reexport.name) { names.append(reexport.name) }
                    pending.append(reexport)
                }
            }
        }
        return names
    }

    /// The images among `candidates` whose symbol table imports any of
    /// `symbolNames` — for a C function or an Objective-C class, the ones
    /// that reach it by that name: a shared cache image keeps those
    /// undefined symbols even where the cache builder bound the calls
    /// directly.
    package func imageIndices(importingAnyOf symbolNames: [String], among candidates: some Sequence<Int>) -> [Int] {
        guard !symbolNames.isEmpty else { return [] }
        let wantedNames = symbolNames.map { strdup($0)! }
        defer { wantedNames.forEach { free($0) } }
        return candidates.filter { imageIndex in
            let linkEdit = linkEdit(ofImageAt: imageIndex)
            for symbolIndex in linkEdit.undefinedSymbolRange ?? linkEdit.symbols.indices {
                let entry = linkEdit.symbols[symbolIndex]
                // An external, undefined symbol.
                guard entry.n_type & 0xE0 == 0, entry.n_type & 0x0E == 0, entry.n_type & 0x01 != 0,
                      let name = linkEdit.name(ofSymbolAt: symbolIndex)
                else { continue }
                for wantedName in wantedNames where strcmp(name, wantedName) == 0 { return true }
            }
            return false
        }
    }
}
