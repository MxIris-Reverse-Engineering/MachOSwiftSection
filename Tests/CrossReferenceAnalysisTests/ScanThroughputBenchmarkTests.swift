import Foundation
import Testing
import CrossReferenceAnalysis

/// How long the operations the module document's throughput table lists
/// take: building the analyzer, a whole table of every image of the
/// running system's shared cache, and the callers of `init` and of
/// `makeKeyAndOrderFront:`. An A/B measurement, not a regression test:
/// run it on the baseline and on the candidate, on the same machine, in a
/// release build, and compare.
///
/// Uses the public API alone, so that the same file runs on both sides
/// (copied into an export of the baseline commit). Runs only with
/// `CROSS_REFERENCE_BENCHMARK_OUTPUT=<file>`, where it writes one line per
/// operation: its name and the best of three rounds, in seconds.
@Suite(
    .enabled(if: ScanThroughputBenchmarkEnvironment.outputPath != nil, "set CROSS_REFERENCE_BENCHMARK_OUTPUT"),
    .serialized
)
struct ScanThroughputBenchmarkTests {
    @Test func scanThroughputAfterTheLayerSplitIsRecordedInTheModuleDocument() throws {
        var lines: [String] = []
        var analyzer: CrossReferenceAnalyzer?
        let analyzerTime = try Self.bestOfThree {
            analyzer = try #require(CrossReferenceAnalyzer())
        }
        let built = try #require(analyzer)
        lines.append("analyzer \(analyzerTime)")

        let allImages = Array(built.imagePaths.indices)
        var referenceCount = 0
        let tableTime = try Self.bestOfThree {
            let counts = UnsafeMutableBufferPointer<Int>.allocate(capacity: allImages.count)
            counts.initialize(repeating: 0)
            defer { counts.deallocate() }
            nonisolated(unsafe) let countsBase = counts.baseAddress!
            DispatchQueue.concurrentPerform(iterations: allImages.count) { imageIndex in
                (countsBase + imageIndex).pointee = built.referenceTable(ofImageAt: imageIndex).references.count
            }
            referenceCount = counts.reduce(0, +)
            if let countsPath = ScanThroughputBenchmarkEnvironment.countsPath {
                let perImage = allImages.map { "\(counts[$0]) \(built.imagePaths[$0])" }.joined(separator: "\n")
                try? (perImage + "\n").write(toFile: countsPath, atomically: true, encoding: .utf8)
            }
        }
        lines.append("wholeCacheTables \(tableTime) references=\(referenceCount)")

        for selector in ["init", "makeKeyAndOrderFront:"] {
            var candidates: [Int] = []
            let prefilterTime = try Self.bestOfThree {
                candidates = built.imageIndices(referencingSelector: selector, among: allImages)
            }
            var senderCount = 0
            let scanTime = try Self.bestOfThree {
                let counts = UnsafeMutableBufferPointer<Int>.allocate(capacity: candidates.count)
                counts.initialize(repeating: 0)
                defer { counts.deallocate() }
                nonisolated(unsafe) let countsBase = counts.baseAddress!
                DispatchQueue.concurrentPerform(iterations: candidates.count) { position in
                    (countsBase + position).pointee = built.references(to: [.selector(selector)], inImageAt: candidates[position]).count
                }
                senderCount = counts.reduce(0, +)
            }
            lines.append("callersOf(\(selector)) prefilter=\(prefilterTime) scan=\(scanTime) images=\(candidates.count) references=\(senderCount)")
        }

        let output = try #require(ScanThroughputBenchmarkEnvironment.outputPath)
        try (lines.joined(separator: "\n") + "\n").write(toFile: output, atomically: true, encoding: .utf8)
    }

    private static func bestOfThree(_ body: () throws -> Void) rethrows -> Double {
        var best = Double.infinity
        for _ in 0 ..< 3 {
            let start = DispatchTime.now().uptimeNanoseconds
            try body()
            best = min(best, Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000)
        }
        return (best * 1000).rounded() / 1000
    }
}

enum ScanThroughputBenchmarkEnvironment {
    static let outputPath = ProcessInfo.processInfo.environment["CROSS_REFERENCE_BENCHMARK_OUTPUT"]
    /// Where to write each image's reference count, to find which images two
    /// sides disagree on when their totals differ.
    static let countsPath = ProcessInfo.processInfo.environment["CROSS_REFERENCE_BENCHMARK_COUNTS"]
}
