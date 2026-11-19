import Foundation
import Testing
@testable import CrossReferenceAnalysis
@_spi(Internals) import MachOCodeReferences
@_spi(Internals) import ObjCCodeReferences

/// Some images' symbol tables put a function start of `__text` below the
/// section's own start. The scan reads such a function where it lies, as it
/// always did; reading it at an offset from `__text` underflowed and trapped
/// the first scan of every image of the macOS 27.2 cache (the throughput
/// benchmark of the layer split, 2026-11-19).
@Suite(.enabled(if: SharedAnalyzer.analyzer != nil, "needs an arm64 process with a dyld shared cache"))
struct FunctionStartOutsideTextTests {
    private var analyzer: CrossReferenceAnalyzer { SharedAnalyzer.analyzer! }

    /// The images whose function table holds a start outside `__text`.
    private func imagesWithAStartOutsideText() -> [Int] {
        let imageCount = analyzer.imagePaths.count
        let flags = UnsafeMutableBufferPointer<Bool>.allocate(capacity: imageCount)
        flags.initialize(repeating: false)
        defer { flags.deallocate() }
        nonisolated(unsafe) let flagsBase = flags.baseAddress!
        let analyzer = self.analyzer
        DispatchQueue.concurrentPerform(iterations: imageCount) { imageIndex in
            let table = analyzer.imageSet.transientFunctionTable(ofImageAt: imageIndex)
            (flagsBase + imageIndex).pointee = table.starts.contains { $0 < table.textStart || $0 >= table.textEnd }
        }
        return (0 ..< imageCount).filter { flags[$0] }
    }

    @Test func aFunctionStartingOutsideTextScansWhereItLies() throws {
        let images = imagesWithAStartOutsideText()
        try #require(!images.isEmpty, "no image of this system's cache has a function start outside __text")
        for imageIndex in images.prefix(3) {
            let table = analyzer.referenceTable(ofImageAt: imageIndex)
            #expect(table.imageIndex == imageIndex, "\(analyzer.imagePaths[imageIndex])")
        }
    }
}
