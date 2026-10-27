import Foundation
import Testing

/// A pointer read out of the process's memory is stripped with the running
/// platform's mask, `InProcessContext.addressMask` — never a constant. A
/// Mac's user addresses fit in 47 bits and an iPhone's in 36, with an arm64e
/// signature starting right above them, at bit 39 on an iPhone: the 47-bit
/// constant the cross-reference scan used left bits 39–46 of every signed
/// slot it read there, and every call through one led nowhere.
@Suite
struct AddressMaskScanTests {
    @Test("no library module strips pointers with an address mask of its own")
    func libraryModulesUseThePlatformMask() throws {
        var offendingLines: [String] = []
        for fileURL in try Self.librarySourceFiles() {
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            for (lineNumber, line) in contents.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), Self.containsAnAddressMask(code) else { continue }
                offendingLines.append("\(fileURL.lastPathComponent):\(lineNumber + 1): \(code)")
            }
        }
        #expect(offendingLines.isEmpty, "strip with `InProcessContext.addressMask`:\n\(offendingLines.joined(separator: "\n"))")
    }

    /// The scan must be able to see a mask, and must not invent one — its
    /// silence proves nothing otherwise.
    @Test("the scan sees an address mask and nothing else")
    func theScanDiscriminates() {
        #expect(Self.containsAnAddressMask("let target = UInt(value & 0x0000_7FFF_FFFF_FFFF)"))
        #expect(Self.containsAnAddressMask("static let addressMask: UInt64 = 0x7FFFFFFFFFFF"))
        #expect(Self.containsAnAddressMask("value & 0x0000_000F_FFFF_FFFF"))
        #expect(Self.containsAnAddressMask("value & 0x7F_FFFF_FFFF"))

        // 32-bit addresses, `Int64.max`, and bits that are no run from bit 0.
        #expect(!Self.containsAnAddressMask("value & 0x7FFF_FFFF"))
        #expect(!Self.containsAnAddressMask("value & 0xFFFF_FFFF"))
        #expect(!Self.containsAnAddressMask("value == 0x7FFF_FFFF_FFFF_FFFF"))
        #expect(!Self.containsAnAddressMask("value & 0x0000_7FFF_FFFF_F000"))
        #expect(!Self.containsAnAddressMask("let shift = 47"))
    }

    private static let hexadecimalLiteral = try! NSRegularExpression(pattern: #"\b0x[0-9A-Fa-f_]+\b"#)

    /// A hexadecimal literal that is a run of 33 to 62 one bits from bit 0:
    /// the width of a user address on some platform.
    private static func containsAnAddressMask(_ code: String) -> Bool {
        hexadecimalLiteral.matches(in: code, range: NSRange(code.startIndex..., in: code)).contains { match in
            guard let range = Range(match.range, in: code),
                  let value = UInt64(code[range].dropFirst(2).filter { $0 != "_" }, radix: 16)
            else { return false }
            return value & (value &+ 1) == 0 && (33 ... 62).contains(value.nonzeroBitCount)
        }
    }

    /// Every Swift file of a library module: `Sources/<Group>/<Module>/…`, the
    /// `TestSupport` group left out.
    private static func librarySourceFiles() throws -> [URL] {
        let sourcesDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // CrossReferenceAnalysisTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // package root
            .appendingPathComponent("Sources")
        let enumerator = try #require(FileManager.default.enumerator(at: sourcesDirectory, includingPropertiesForKeys: nil))
        var files: [URL] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let groupName = fileURL.pathComponents.drop(while: { $0 != "Sources" }).dropFirst().first
            if groupName == "TestSupport" { continue }
            files.append(fileURL)
        }
        #expect(files.count > 100, "found only \(files.count) library sources under \(sourcesDirectory.path)")
        return files
    }
}
