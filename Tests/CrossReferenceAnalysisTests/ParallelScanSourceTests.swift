import Foundation
import Testing

/// Every parallel scan of this target goes through `ImageScanConcurrency`,
/// whose one budget keeps the suites Swift Testing runs at once from taking
/// every core between them (evolution proposal
/// `cross-reference-test-scan-load`). The throughput benchmark is the
/// exception: it measures the scan on every core, and runs only when asked.
@Suite
struct ParallelScanSourceTests {
    /// The budget itself, the benchmark, and this file, whose discrimination
    /// test spells the call it looks for.
    private static let filesAllowedToCallDispatchDirectly: Set<String> = [
        "ImageScanConcurrency.swift",
        "ScanThroughputBenchmarkTests.swift",
        "ParallelScanSourceTests.swift",
    ]

    @Test func everyParallelScanGoesThroughTheSharedBudget() throws {
        let fileURLs = try Self.targetSourceFiles()
        try #require(fileURLs.contains { $0.lastPathComponent == "ImageScanConcurrency.swift" }, "not this target's directory")
        var offendingLines: [String] = []
        for fileURL in fileURLs where !Self.filesAllowedToCallDispatchDirectly.contains(fileURL.lastPathComponent) {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            for (lineNumber, line) in contents.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), Self.callsDispatchDirectly(code) else { continue }
                offendingLines.append("\(fileURL.lastPathComponent):\(lineNumber + 1): \(code)")
            }
        }
        #expect(offendingLines.isEmpty, "scan through `ImageScanConcurrency.concurrentPerform`:\n\(offendingLines.joined(separator: "\n"))")
    }

    /// The scan must see a direct call, and nothing else — its silence proves
    /// nothing otherwise.
    @Test func theScanDiscriminates() {
        #expect(Self.callsDispatchDirectly("DispatchQueue.concurrentPerform(iterations: imageIndices.count) { position in"))
        #expect(Self.callsDispatchDirectly("DispatchQueue.concurrentPerform(iterations: imageCount, execute: readTrie)"))
        #expect(!Self.callsDispatchDirectly("ImageScanConcurrency.concurrentPerform(iterations: imageIndices.count) { position in"))
        #expect(!Self.callsDispatchDirectly("DispatchQueue.global().async {"))
    }

    private static func callsDispatchDirectly(_ code: String) -> Bool {
        code.contains("DispatchQueue.concurrentPerform(")
    }

    private static func targetSourceFiles() throws -> [URL] {
        let targetDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()  // CrossReferenceAnalysisTests
        return try FileManager.default
            .contentsOfDirectory(at: targetDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
    }
}
