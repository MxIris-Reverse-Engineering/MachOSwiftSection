import Foundation
import Testing
@testable import CrossReferenceAnalysis

/// Foundation's index, built once for the suite: a Debug build scans an image
/// of its size in seconds.
private enum FoundationIndex {
    static let imageIndex = SharedAnalyzer.analyzer?.imagePaths.firstIndex { $0.hasSuffix("/Foundation.framework/Versions/C/Foundation") }
    static let index = imageIndex.flatMap { SharedAnalyzer.analyzer?.referenceIndex(ofImageAt: $0) }
}

/// A ``CodeReferenceIndex`` answers what a scan of its image would, at a
/// fraction of a whole table's memory.
@Suite(.enabled(if: SharedAnalyzer.analyzer != nil, "needs an arm64 process with a dyld shared cache"))
struct CodeReferenceIndexTests {
    private var analyzer: CrossReferenceAnalyzer { SharedAnalyzer.analyzer! }

    private func imageIndex(endingWith suffix: String) throws -> Int {
        try #require(analyzer.imagePaths.firstIndex { $0.hasSuffix(suffix) }, "no image ending with \(suffix)")
    }

    /// Every key a whole table files references under, the index files the
    /// same references under, in the same order; and it keeps nothing else
    /// but the Swift type names, which a type query reads.
    @Test func indexFilesEveryKeyLikeTheTable() throws {
        let foundation = try #require(FoundationIndex.imageIndex)
        let index = try #require(FoundationIndex.index)
        let table = analyzer.referenceTable(ofImageAt: foundation)
        var mismatchedKeys: [CodeReferenceTable.Key] = []
        for key in table.keys where index.references(to: [key]) != table.references(to: key) {
            if mismatchedKeys.count < 5 { mismatchedKeys.append(key) }
        }
        #expect(mismatchedKeys.isEmpty, "\(mismatchedKeys)")
        let keptReferences = table.references.filter { reference in
            if reference.target.tableKey != nil { return true }
            if case .swiftTypeName = reference.target { return true }
            return false
        }
        #expect(index.referenceCount == keptReferences.count)
        #expect(index.referenceCount < table.references.count)
    }

    /// Several keys at once — a selector, a function in another image, a
    /// class — come back exactly as a scan filtered by them finds them.
    @Test func indexAnswersAQueryLikeAFilteredScan() throws {
        let appKit = try imageIndex(endingWith: "/AppKit.framework/Versions/C/AppKit")
        let swiftCore = try imageIndex(endingWith: "/libswiftCore.dylib")
        let beginAccess = try #require(analyzer.functions(inImageAt: swiftCore).first { $0.name == .symbol("_swift_beginAccess") })
        let keys: Set<CodeReferenceTable.Key> = [.selector("orderWindow:relativeTo:"), .function(beginAccess.location), .objectiveCClass("NSWindow")]
        let index = analyzer.referenceIndex(ofImageAt: appKit)
        let fromIndex = index.references(to: keys)
        #expect(!fromIndex.isEmpty)
        #expect(fromIndex == analyzer.references(to: keys, inImageAt: appKit))
    }

    /// A Swift type's references — by descriptor and metadata, by the names
    /// that mention it, and for a class by its class object — come back as a
    /// scan for the type finds them. `Sa` is spelled out in names rather than
    /// referred to, which takes demangling them.
    @Test(arguments: [
        ("/Foundation.framework/Versions/C/Foundation", "10Foundation3URLV"),
        ("/Foundation.framework/Versions/C/Foundation", "10Foundation11JSONEncoderC"),
        ("/usr/lib/swift/libswiftCore.dylib", "Sa"),
    ])
    func indexFindsSwiftTypesLikeTheScan(definingImageSuffix: String, key: String) throws {
        let foundation = try #require(FoundationIndex.imageIndex)
        let index = try #require(FoundationIndex.index)
        let definer = try imageIndex(endingWith: definingImageSuffix)
        let location = try #require(analyzer.swiftTypeDescriptorLocations(withKey: key, inImageAt: definer).first, "no type \(key)")
        let identity = try #require(analyzer.swiftTypeIdentity(ofDescriptorAt: location))
        let fromIndex = analyzer.references(toSwiftType: identity, in: index)
        #expect(!fromIndex.isEmpty)
        #expect(fromIndex == analyzer.references(toSwiftType: identity, inImageAt: foundation))
    }

    /// What lets a host keep an index for every image it has open.
    @Test func indexIsAFractionOfTheTable() throws {
        let foundation = try #require(FoundationIndex.imageIndex)
        let index = try #require(FoundationIndex.index)
        let table = analyzer.referenceTable(ofImageAt: foundation)
        #expect(index.approximateByteCount * 2 < table.approximateByteCount, "index \(index.approximateByteCount) bytes, table \(table.approximateByteCount) bytes")
    }

    /// Naming what an index answers needs the image's function table, which
    /// building the index keeps — unlike a whole-image scan for a table.
    @Test func buildingAnIndexKeepsTheFunctionTable() throws {
        let freshAnalyzer = try #require(CrossReferenceAnalyzer())
        let libobjc = try #require(freshAnalyzer.imagePaths.firstIndex { $0.hasSuffix("/usr/lib/libobjc.A.dylib") })
        #expect(freshAnalyzer.existingFunctionTable(ofImageAt: libobjc) == nil)
        _ = freshAnalyzer.referenceIndex(ofImageAt: libobjc)
        #expect(freshAnalyzer.existingFunctionTable(ofImageAt: libobjc) != nil)
    }

    /// Progress is reported from the first function to the last, and a
    /// report answered with "stop" ends the scan without an index.
    @Test func progressReportsAndStops() throws {
        let libobjc = try imageIndex(endingWith: "/usr/lib/libobjc.A.dylib")
        var reports: [(Int, Int)] = []
        let index = analyzer.referenceIndex(ofImageAt: libobjc) { scannedFunctionCount, functionCount in
            reports.append((scannedFunctionCount, functionCount))
            return true
        }
        #expect(index != nil)
        let functionCount = try #require(reports.last?.1)
        #expect(reports.first?.0 == 0)
        #expect(reports.last?.0 == functionCount)
        #expect(reports.allSatisfy { $0.1 == functionCount })

        var stoppedReportCount = 0
        let stopped = analyzer.referenceIndex(ofImageAt: libobjc) { _, _ in
            stoppedReportCount += 1
            return false
        }
        #expect(stopped == nil)
        #expect(stoppedReportCount == 1)
    }
}
