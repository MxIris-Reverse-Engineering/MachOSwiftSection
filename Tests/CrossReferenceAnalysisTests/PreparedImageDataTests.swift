import Foundation
import Testing
@testable import CrossReferenceAnalysis

/// What a host prepares ahead of its queries — an image's names, the
/// prefilters' tables — is what a query would otherwise read first, and stays
/// until the host releases it. Each test makes an analyzer of its own: what
/// they check is what an analyzer keeps.
@Suite(.enabled(if: SharedAnalyzer.analyzer != nil, "needs an arm64 process with a dyld shared cache"))
struct PreparedImageDataTests {
    private static func imageIndex(endingWith suffix: String, in analyzer: CrossReferenceAnalyzer) throws -> Int {
        try #require(analyzer.imagePaths.firstIndex { $0.hasSuffix(suffix) }, "no image ending with \(suffix)")
    }

    /// After `prepareNames(inImageAt:)`, naming a function and looking up a
    /// class or a type read nothing more — and the names are the ones a query
    /// reads on its own.
    @Test func preparedNamesAreWhatAQueryReads() throws {
        let analyzer = try #require(CrossReferenceAnalyzer())
        let foundation = try Self.imageIndex(endingWith: "/Foundation.framework/Versions/C/Foundation", in: analyzer)
        #expect(analyzer.existingFunctionTable(ofImageAt: foundation) == nil)
        #expect(analyzer.approximateByteCount(ofImageDataAt: foundation) == 0)

        analyzer.prepareNames(inImageAt: foundation)
        let table = try #require(analyzer.existingFunctionTable(ofImageAt: foundation))
        #expect(table.existingFallbackNames?.hasReadEverySource == true)
        let indexes = analyzer.existingIndexes(ofImageAt: foundation)
        #expect(indexes.classIndex?.hasReadEveryName == true)
        #expect(indexes.swiftTypeIndex?.builtState.hasReadDescriptorSymbols == true)

        let lazilyNamed = try #require(CrossReferenceAnalyzer()).functions(inImageAt: foundation)
        #expect(lazilyNamed.count > 10000)
        #expect(analyzer.functions(inImageAt: foundation) == lazilyNamed)
    }

    /// The estimate follows what is kept: the function table alone, then the
    /// names read for it; nothing once released.
    @Test func estimateFollowsWhatIsKept() throws {
        let analyzer = try #require(CrossReferenceAnalyzer())
        let libobjc = try Self.imageIndex(endingWith: "/usr/lib/libobjc.A.dylib", in: analyzer)
        analyzer.keepFunctionTable(ofImageAt: libobjc)
        let tableBytes = analyzer.approximateByteCount(ofImageDataAt: libobjc)
        #expect(tableBytes > 0)
        analyzer.prepareNames(inImageAt: libobjc)
        #expect(analyzer.approximateByteCount(ofImageDataAt: libobjc) > tableBytes)
        analyzer.releaseImageData(exceptForImagesAt: [])
        #expect(analyzer.approximateByteCount(ofImageDataAt: libobjc) == 0)
    }

    /// Releasing keeps the images asked for, with what was read for them,
    /// and drops the rest — which a later query reads again.
    @Test func releasingKeepsTheImagesAskedFor() throws {
        let analyzer = try #require(CrossReferenceAnalyzer())
        let libobjc = try Self.imageIndex(endingWith: "/usr/lib/libobjc.A.dylib", in: analyzer)
        let foundation = try Self.imageIndex(endingWith: "/Foundation.framework/Versions/C/Foundation", in: analyzer)
        analyzer.prepareNames(inImageAt: libobjc)
        analyzer.prepareNames(inImageAt: foundation)
        let keptBytes = analyzer.approximateByteCount(ofImageDataAt: libobjc)

        analyzer.releaseImageData(exceptForImagesAt: [libobjc])
        #expect(analyzer.existingFunctionTable(ofImageAt: libobjc)?.existingFallbackNames?.hasReadEverySource == true)
        #expect(analyzer.existingIndexes(ofImageAt: libobjc).classIndex?.hasReadEveryName == true)
        #expect(analyzer.approximateByteCount(ofImageDataAt: libobjc) == keptBytes)
        #expect(analyzer.existingFunctionTable(ofImageAt: foundation) == nil)
        #expect(analyzer.existingIndexes(ofImageAt: foundation).classIndex == nil)
        #expect(analyzer.existingIndexes(ofImageAt: foundation).swiftTypeIndex == nil)
        #expect(analyzer.approximateByteCount(ofImageDataAt: foundation) == 0)
        #expect(!analyzer.functions(inImageAt: foundation).isEmpty)
    }

    /// The prefilters' tables, prepared on one thread while a query asks for
    /// them on another, are built once: the query waits instead of reading
    /// every export trie again.
    @Test func prefiltersAreBuiltOnce() async throws {
        let analyzer = try #require(CrossReferenceAnalyzer())
        let preparing = Task.detached { analyzer.preparePrefilters() }
        let asking = Task.detached { analyzer.renamedReexports().reexportsByProvider.count }
        await preparing.value
        let providerCount = await asking.value
        #expect(analyzer.hasPreparedPrefilters)
        #expect(providerCount > 0)
        #expect(analyzer.renamedReexportBuildCount == 1)
    }

    /// Reading the export tries on the calling thread alone finds what
    /// reading them on every core finds, in the same order.
    @Test func serialAndConcurrentReadsAgree() throws {
        let analyzer = try #require(CrossReferenceAnalyzer())
        let serial = RenamedReexportIndex(analyzer: analyzer, concurrently: false)
        let concurrent = RenamedReexportIndex(analyzer: analyzer, concurrently: true)
        #expect(serial.reexportsByProvider.values.reduce(0) { $0 + $1.count } > 1000)
        #expect(serial.reexportsByProvider == concurrent.reexportsByProvider)
    }
}
