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
        var providers: Set<Int> = [imageIndex]
        var pending = [imageIndex]
        while let provider = pending.popLast() {
            for reexporter in linkage.reexporters[provider] ?? [] where providers.insert(reexporter).inserted {
                pending.append(reexporter)
            }
        }
        var linkers = providers
        for provider in providers {
            linkers.formUnion(linkage.dependents[provider] ?? [])
        }
        return candidates.filter(linkers.contains)
    }

    /// The images among `candidates` that can call the function at
    /// `location`, which its image names `symbolNames`: its own image; for a
    /// C or Objective-C name, the images importing it; for a Swift name,
    /// which few cache images keep among their undefined symbols, every image
    /// that can bind to the function's image.
    public func imageIndices(callingFunctionAt location: CodeLocation, symbolNames: [String], among candidates: some Sequence<Int>) -> [Int] {
        let candidates = Array(candidates)
        var result = Set<Int>()
        if candidates.contains(location.imageIndex) { result.insert(location.imageIndex) }
        let swiftNames = symbolNames.filter(Self.isSwiftSymbolName)
        let otherNames = symbolNames.filter { !Self.isSwiftSymbolName($0) }
        if !otherNames.isEmpty {
            result.formUnion(imageIndices(importingAnyOf: otherNames, among: candidates))
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
