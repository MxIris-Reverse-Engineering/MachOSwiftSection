import Foundation

extension CrossReferenceAnalyzer {
    /// The images among `candidates` that can bind to the symbols of the
    /// image at `imageIndex`: the image itself, the images re-exporting it —
    /// SwiftUI re-exports SwiftUICore — and every image linking one of those.
    public func imageIndices(linkingImageAt imageIndex: Int, among candidates: some Sequence<Int>) -> [Int] {
        imageSet.imageIndices(linkingImageAt: imageIndex, among: candidates)
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
        imageSet.reexportedNames(ofSymbolsNamed: symbolNames, inImageAt: imageIndex)
    }

    /// The images among `candidates` that can call the function at
    /// `location`, which its image names `symbolNames`: its own image; for a
    /// C or Objective-C name, the images importing it, by that name or by
    /// one another image re-exports it under; for a Swift name, which few
    /// cache images keep among their undefined symbols, every image that can
    /// bind to the function's image (`Linkage`).
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
