import Foundation
import Testing
import MachOKit
@testable import CrossReferenceAnalysis
@_spi(Internals) import MachOCodeReferences
@_spi(Internals) import ObjCCodeReferences

/// Some images' symbol tables put a function start of `__text` below the
/// section's own start. The scan reads such a function where it lies, as it
/// always did; reading it at an offset from `__text` underflowed and trapped
/// the first scan of every image of the macOS 27.2 cache (the throughput
/// benchmark of the layer split, 2026-11-19).
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
        ImageScanConcurrency.concurrentPerform(iterations: imageCount) { imageIndex in
            let table = analyzer.imageSet.transientFunctionTable(ofImageAt: imageIndex)
            (flagsBase + imageIndex).pointee = table.starts.contains { $0 < table.textStart || $0 >= table.textEnd }
        }
        return (0 ..< imageCount).filter { flags[$0] }
    }

    @Test(.enabled(if: SharedAnalyzer.analyzer != nil, "needs an arm64 process with a dyld shared cache"))
    func aFunctionStartingOutsideTextScansWhereItLies() throws {
        let images = imagesWithAStartOutsideText()
        try #require(!images.isEmpty, "no image of this system's cache has a function start outside __text")
        for imageIndex in images.prefix(3) {
            let table = analyzer.referenceTable(ofImageAt: imageIndex)
            #expect(table.imageIndex == imageIndex, "\(analyzer.imagePaths[imageIndex])")
        }
    }

    /// A main executable's symbol table files `__mh_execute_header` — the
    /// Mach header itself, at the start of `__TEXT` — under `__text`, so the
    /// header and the load commands scan as a function below the section.
    /// An index counted its offsets from `__text` and could not hold a
    /// reference made there: a Debug build trapped on its assertion, and a
    /// Release build stored the offset truncated and named a function 4 GiB
    /// away (RuntimeViewer indexing iOS 27's `Preferences`, 2026-11-20). A
    /// call planted in the padding before `__text` stands for whatever the
    /// load commands happen to decode to.
    @Test func anIndexKeepsTheReferencesOfAFunctionBelowText() throws {
        let (directory, executable) = try CompiledFixture.build(
            libraryName: "Executable",
            sources: ["Main.c": """
            __attribute__((noinline)) void target(void) { __asm__ volatile(""); }
            int main(void) {
                target();
                return 0;
            }
            """],
            compilerArguments: ["-O1"],
            isExecutable: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let linked = try MachOFile(url: executable)
        let textSection = try #require(linked.sections64.first { $0.segmentName == "__TEXT" && $0.sectionName == "__text" })
        let loadCommandsEnd = MemoryLayout<mach_header_64>.size + Int(linked.header.sizeofcmds)
        let siteOffset = textSection.offset - 4
        try #require(siteOffset >= loadCommandsEnd, "no padding between the load commands and __text")
        let siteAddress = UInt64(textSection.address) - 4
        let linkedAnalyzer = try CrossReferenceAnalyzer(machOFiles: [linked])
        let target = try #require(linkedAnalyzer.functions(inImageAt: 0).first { $0.name == .symbol("_target") })
        var bytes = try Data(contentsOf: executable)
        let call = InstructionEncoding.branchWithLink(at: siteAddress, to: target.location.address)
        withUnsafeBytes(of: call.littleEndian) { bytes.replaceSubrange(siteOffset ..< siteOffset + 4, with: $0) }
        let patched = directory.appendingPathComponent("PatchedExecutable")
        try bytes.write(to: patched)

        let analyzer = try CrossReferenceAnalyzer(machOFiles: [MachOFile(url: patched)])
        let functionTable = analyzer.imageSet.transientFunctionTable(ofImageAt: 0)
        let headerFunction = try #require(functionTable.starts.first)
        try #require(headerFunction < functionTable.textStart, "the executable's first function start lies in __text")
        let table = analyzer.referenceTable(ofImageAt: 0)
        let plantedCall = table.references(to: .function(target.location)).first { $0.instructionAddress == siteAddress }
        #expect(plantedCall?.function.address == headerFunction, "\(table.references(to: .function(target.location)))")

        let index = analyzer.referenceIndex(ofImageAt: 0)
        var mismatchedKeys: [CodeReferenceTable.Key] = []
        for key in table.keys where index.references(to: [key]) != table.references(to: key) {
            mismatchedKeys.append(key)
        }
        #expect(mismatchedKeys.isEmpty, "\(mismatchedKeys)")
    }
}
