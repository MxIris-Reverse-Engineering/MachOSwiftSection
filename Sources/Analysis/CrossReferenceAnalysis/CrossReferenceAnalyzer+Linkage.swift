import Foundation
import MachOKit

/// Which images link which: what tells the images that can bind to another
/// image's Swift symbols.
///
/// Only 245 of the macOS 27.2 shared cache's 4,113 images keep any Swift
/// symbol among their undefined symbols. The rest bind Swift symbols with
/// nothing left to show: SharedWithYou keeps 314 undefined symbols, all C
/// functions and Objective-C classes, yet calls `URL`'s metadata accessor
/// through a GOT stub the cache builder bound; 44 images import `URL.path`
/// by name, and many more call it. A Swift symbol another image uses is told
/// by the linkage instead: an image binds only to the images it links and
/// the ones those re-export.
struct Linkage {
    /// The images that link each image.
    let dependents: [Int: [Int]]
    /// The images that re-export each image.
    let reexporters: [Int: [Int]]
}

extension CrossReferenceAnalyzer {
    /// The images among `candidates` that can bind to the symbols of the
    /// image at `imageIndex`: the image itself, the images re-exporting it —
    /// SwiftUI re-exports SwiftUICore — and every image linking one of those.
    public func imageIndices(linkingImageAt imageIndex: Int, among candidates: some Sequence<Int>) -> [Int] {
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
    public func reexportedNames(ofSymbolsNamed symbolNames: [String], inImageAt imageIndex: Int) -> [String] {
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

    /// The images among `candidates` that can call the function at
    /// `location`, which its image names `symbolNames`: its own image; for a
    /// C or Objective-C name, the images importing it, by that name or by
    /// one another image re-exports it under; for a Swift name, which few
    /// cache images keep among their undefined symbols, every image that can
    /// bind to the function's image.
    public func imageIndices(callingFunctionAt location: CodeLocation, symbolNames: [String], among candidates: some Sequence<Int>) -> [Int] {
        let candidates = Array(candidates)
        var result = Set<Int>()
        if candidates.contains(location.imageIndex) { result.insert(location.imageIndex) }
        let swiftNames = symbolNames.filter(Self.isSwiftSymbolName)
        let otherNames = symbolNames.filter { !Self.isSwiftSymbolName($0) }
        if !otherNames.isEmpty {
            let importedNames = otherNames + reexportedNames(ofSymbolsNamed: otherNames, inImageAt: location.imageIndex)
            result.formUnion(imageIndices(importingAnyOf: importedNames, among: candidates))
        }
        if !swiftNames.isEmpty {
            result.formUnion(imageIndices(linkingImageAt: location.imageIndex, among: candidates))
        }
        return result.sorted()
    }

    /// `_$s…`, or `$s…` without the C prefix.
    static func isSwiftSymbolName(_ name: String) -> Bool {
        name.hasPrefix("_$s") || name.hasPrefix("$s")
    }
}
