import Foundation
import Testing
@testable import CrossReferenceAnalysis
@_spi(Internals) import MachOCodeReferences
@_spi(Internals) import ObjCCodeReferences

/// What the language layers' sessions do inside the analyzer. That the
/// core's scan takes any recognizer, with no language layer present at all,
/// is MachOKitExtensions' `CoreOnlyScanTests` (proposal
/// `move-cross-reference-layers`).
@Suite(.enabled(if: SharedAnalyzer.analyzer != nil, "needs an arm64 process with a dyld shared cache"))
struct RecognizerExtensionPointTests {
    /// A query for the senders of a selector looks up no Swift type: the
    /// Swift session skips its accessors, metadata and mangled names when the
    /// query keeps none of them.
    @Test func selectorQueriesLookUpNoSwiftType() throws {
        let freshAnalyzer = try #require(CrossReferenceAnalyzer())
        let swiftUICore = try #require(freshAnalyzer.imagePaths.firstIndex { $0.hasSuffix("/SwiftUICore.framework/Versions/A/SwiftUICore") })
        let sends = freshAnalyzer.references(to: [.selector("init")], inImageAt: swiftUICore)
        #expect(!sends.isEmpty)
        let builtTypeIndexes = freshAnalyzer.imagePaths.indices.filter { freshAnalyzer.existingIndexes(ofImageAt: $0).swiftTypeIndex != nil }
        #expect(builtTypeIndexes.isEmpty, "type indexes built for \(builtTypeIndexes.map { freshAnalyzer.imagePaths[$0] })")
    }
}
