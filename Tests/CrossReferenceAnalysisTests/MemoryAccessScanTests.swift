import Foundation
import Testing

/// Every read of image memory in the cross-reference analysis — its core,
/// its Objective-C layer and `CrossReferenceAnalysis` — goes through
/// `CrossReferenceMemory`, so that an analyzer can read images that were
/// never loaded: an address turned into a pointer anywhere else reads the
/// process's memory whatever the analyzer was made from.
@Suite
struct MemoryAccessScanTests {
    /// The one file allowed to turn an address into a pointer.
    static let inProcessMemoryFileName = "InProcessCrossReferenceMemory.swift"

    @Test func crossReferenceAnalysisReadsMemoryOnlyThroughCrossReferenceMemory() throws {
        var offendingLines: [String] = []
        let files = try Self.moduleSourceFiles()
        #expect(files.contains { $0.lastPathComponent == Self.inProcessMemoryFileName }, "the scan does not see \(Self.inProcessMemoryFileName)")
        for fileURL in files where fileURL.lastPathComponent != Self.inProcessMemoryFileName {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            for (lineNumber, line) in contents.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), Self.turnsAnAddressIntoAPointer(code) else { continue }
                offendingLines.append("\(fileURL.lastPathComponent):\(lineNumber + 1): \(code)")
            }
        }
        #expect(offendingLines.isEmpty, "read through `CrossReferenceMemory`:\n\(offendingLines.joined(separator: "\n"))")
    }

    /// The scan must see a pointer made from an address, and nothing else —
    /// its silence proves nothing otherwise.
    @Test func theScanDiscriminates() {
        #expect(Self.turnsAnAddressIntoAPointer("guard let slot = UnsafeRawPointer(bitPattern: address) else {"))
        #expect(Self.turnsAnAddressIntoAPointer("let name = UnsafePointer<CChar>(bitPattern: string)"))
        #expect(Self.turnsAnAddressIntoAPointer("UnsafeMutableRawPointer(bitPattern: 0x1000)"))
        #expect(!Self.turnsAnAddressIntoAPointer("let key = UInt(bitPattern: pointer)"))
        #expect(!Self.turnsAnAddressIntoAPointer("UInt(bitPattern: Int(bitPattern: UInt(address)) &+ slide)"))
        #expect(!Self.turnsAnAddressIntoAPointer("let raw = UnsafeRawPointer(bytes + index)"))
    }

    private static let pointerFromAddress = try! NSRegularExpression(pattern: #"Unsafe(Mutable)?(Raw)?Pointer(<[^>]*>)?\(bitPattern:"#)

    private static func turnsAnAddressIntoAPointer(_ code: String) -> Bool {
        pointerFromAddress.firstMatch(in: code, range: NSRange(code.startIndex..., in: code)) != nil
    }

    /// Every Swift file of the three cross-reference modules.
    private static func moduleSourceFiles() throws -> [URL] {
        let analysisDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // CrossReferenceAnalysisTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appendingPathComponent("Sources/Analysis")
        var files: [URL] = []
        for moduleName in ["CrossReferenceCore", "CrossReferenceObjC", "CrossReferenceAnalysis"] {
            let moduleDirectory = analysisDirectory.appendingPathComponent(moduleName)
            let enumerator = try #require(FileManager.default.enumerator(at: moduleDirectory, includingPropertiesForKeys: nil))
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
                files.append(fileURL)
            }
        }
        #expect(files.count > 25, "found only \(files.count) sources under \(analysisDirectory.path)")
        return files
    }
}
