import Foundation
import Testing
import MachOKit
@testable import CrossReferenceAnalysis

/// A function or a class that another image re-exports under a name of its
/// own is imported by that name, and the prefilters keep its importers:
/// AppKit calls libsystem_platform's `__platform_strlen` as libsystem_c's
/// `_strlen`, and SkyLight's `_SLSMainConnectionID` as CoreGraphics'
/// `_CGSMainConnectionID` — one of 273 SkyLight functions it reaches through
/// CoreGraphics' names on macOS 27.2.
@Suite(.enabled(if: SharedAnalyzer.analyzer != nil, "needs an arm64 process with a dyld shared cache"))
struct RenamedReexportTests {
    private var analyzer: CrossReferenceAnalyzer { SharedAnalyzer.analyzer! }

    private func imageIndex(endingWith suffix: String) throws -> Int {
        try #require(analyzer.imagePaths.firstIndex { $0.hasSuffix(suffix) }, "no image ending with \(suffix)")
    }

    @Test(arguments: zip(
        ["/usr/lib/system/libsystem_platform.dylib", "/SkyLight.framework/Versions/A/SkyLight"],
        ["__platform_strlen", "_SLSMainConnectionID"]
    ))
    func callersImportingARenamedReexportAreKept(imageSuffix: String, symbol: String) throws {
        let owner = try imageIndex(endingWith: imageSuffix)
        let appKit = try imageIndex(endingWith: "/AppKit.framework/Versions/C/AppKit")
        let function = try #require(analyzer.functions(inImageAt: owner).first { $0.name == .symbol(symbol) || $0.foldedSymbolNames.contains(symbol) }, "no function \(symbol)")
        // AppKit does call it.
        #expect(!analyzer.references(to: [.function(function.location)], inImageAt: appKit).isEmpty)
        let kept = analyzer.imageIndices(callingFunctionAt: function.location, symbolNames: [symbol], among: analyzer.images.indices)
        #expect(kept.contains(appKit))
    }

    /// The names come from every image's export trie, and follow a
    /// re-export made through an umbrella: acfsSupport re-exports
    /// `_kMDConfigErase`, which Metadata defines, from CoreServices, which
    /// re-exports Metadata whole.
    @Test func reexportedNamesSpellWhatCallersImport() throws {
        let platform = try imageIndex(endingWith: "/usr/lib/system/libsystem_platform.dylib")
        let strlenNames = analyzer.reexportedNames(ofSymbolsNamed: ["__platform_strlen"], inImageAt: platform)
        #expect(strlenNames == ["_strlen"])
        let metadata = try imageIndex(endingWith: "/Metadata.framework/Versions/A/Metadata")
        #expect(analyzer.reexportedNames(ofSymbolsNamed: ["_kMDConfigErase"], inImageAt: metadata) == ["_xkMDConfigErase"])
        #expect(analyzer.reexportedNames(ofSymbolsNamed: ["_strlen"], inImageAt: platform).isEmpty)
    }

    /// UIFoundation re-exports CoreText's `CTEmojiImageAsset` as
    /// `NSEmojiImageAsset`, which is the name CharacterPicker imports.
    @Test func importersOfARenamedClassAreKept() throws {
        let coreText = try imageIndex(endingWith: "/CoreText.framework/Versions/A/CoreText")
        let characterPicker = try imageIndex(endingWith: "/CharacterPicker.framework/Versions/A/CharacterPicker")
        let location = try #require(analyzer.objectiveCClassLocations(named: "CTEmojiImageAsset", inImageAt: coreText).first)
        #expect(analyzer.imageIndices(referencingObjectiveCClassAt: location, among: analyzer.images.indices).contains(characterPicker))
    }
}
