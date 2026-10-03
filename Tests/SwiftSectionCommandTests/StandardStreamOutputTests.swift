import Foundation
import Testing
@preconcurrency import Rainbow
import Semantic
import SwiftSectionKit
@testable import swift_section

/// Where the command line puts a request's output, and in which bytes. The
/// streams are memory streams here, so the tests read back exactly what a
/// terminal or a redirect would have received.
///
/// Serialized because `Rainbow.enabled` is process-wide: the tests pin colors
/// off (or on) for their own duration.
@Suite(.serialized)
struct StandardStreamOutputTests {
    /// Runs `body` against two memory streams and returns what each received.
    private func capture(
        standardOutputSeverities: Set<SwiftSectionDiagnostic.Severity> = [],
        colorsEnabled: Bool = false,
        _ body: (StandardStreamOutput) -> Void
    ) -> (standardOutput: String, standardError: String) {
        // Rainbow colors only when enabled AND writing to a console; a test
        // process's stdout is usually neither, so both are pinned.
        let previousColorsEnabled = Rainbow.enabled
        let previousOutputTarget = Rainbow.outputTarget
        Rainbow.enabled = colorsEnabled
        Rainbow.outputTarget = .console
        defer {
            Rainbow.enabled = previousColorsEnabled
            Rainbow.outputTarget = previousOutputTarget
        }

        var standardOutputBuffer: UnsafeMutablePointer<CChar>?
        var standardOutputSize = 0
        var standardErrorBuffer: UnsafeMutablePointer<CChar>?
        var standardErrorSize = 0
        guard let standardOutputStream = open_memstream(&standardOutputBuffer, &standardOutputSize),
              let standardErrorStream = open_memstream(&standardErrorBuffer, &standardErrorSize)
        else {
            Issue.record("open_memstream failed")
            return ("", "")
        }
        body(StandardStreamOutput(
            standardOutputSeverities: standardOutputSeverities,
            standardOutput: standardOutputStream,
            standardError: standardErrorStream
        ))
        fclose(standardOutputStream)
        fclose(standardErrorStream)
        defer {
            free(standardOutputBuffer)
            free(standardErrorBuffer)
        }
        return (
            standardOutputBuffer.map { String(cString: $0) } ?? "",
            standardErrorBuffer.map { String(cString: $0) } ?? ""
        )
    }

    @Test("Every piece of the product goes to stdout followed by a newline")
    func productPieces() {
        let captured = capture { output in
            output.write(.text("report"))
            output.write(.data(Data("{}".utf8)))
            output.write(.annotatedInterface("+added\n-removed", style: .diff(isUnifiedDiff: false)))
            output.write(.declarations("struct Declaration {}"))
            output.write(.text(""))
        }
        #expect(captured.standardOutput == "report\n{}\n+added\n-removed\nstruct Declaration {}\n\n")
        #expect(captured.standardError.isEmpty)
    }

    @Test("Diagnostics go to stderr unless the command routes their severity to stdout")
    func diagnosticRouting() {
        let captured = capture(standardOutputSeverities: [.progress]) { output in
            output.report(SwiftSectionDiagnostic(severity: .progress, message: "Building Swift interface..."))
            output.report(SwiftSectionDiagnostic(severity: .warning, message: "warning: something degraded"))
            output.report(SwiftSectionDiagnostic(severity: .note, message: "no unions found in Sample"))
        }
        #expect(captured.standardOutput == "Building Swift interface...\n")
        #expect(captured.standardError == "warning: something degraded\nno unions found in Sample\n")
    }

    /// `dump` has always printed a declaration's failure in red, in line with
    /// the declarations around it.
    @Test("An error routed to stdout is red when colors are on")
    func errorOnStandardOutputIsRed() {
        let captured = capture(standardOutputSeverities: [.error], colorsEnabled: true) { output in
            output.report(SwiftSectionDiagnostic(severity: .error, message: "failed"))
        }
        #expect(captured.standardOutput.hasPrefix("\u{1B}[31m"))
        #expect(captured.standardOutput.contains("failed"))
    }

    @Test("Annotated lines are colored by their kind when colors are on")
    func annotatedLinesAreColored() {
        let captured = capture(colorsEnabled: true) { output in
            output.write(.annotatedInterface("+added\n kept", style: .diff(isUnifiedDiff: false)))
        }
        let lines = captured.standardOutput.split(separator: "\n")
        #expect(lines.first?.hasPrefix("\u{1B}[32m") == true)
        #expect(lines.last == " kept")
    }
}

/// Every byte the command line writes goes through `StandardStreamOutput`,
/// which writes with `fwrite`. The `objc` subcommands used to write through
/// `FileHandle.standardOutput/standardError.write(_:)`, whose Objective-C
/// bridge raises an exception Swift cannot catch on a closed stream and aborts
/// the process; the Swift side had already been fixed for `snapshot`. A source
/// scan keeps the whole class out, not just the instances that were found.
@Suite
struct CommandLineStreamWriteScanTests {
    private static let commandLineSourcesDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // SwiftSectionCommandTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // package root
        .appendingPathComponent("Sources/Executables/swift-section")

    @Test("No command-line source writes to a process stream except StandardStreamOutput")
    func streamWritesGoThroughTheOutput() throws {
        let enumerator = try #require(FileManager.default.enumerator(at: Self.commandLineSourcesDirectory, includingPropertiesForKeys: nil))
        var scannedFileCount = 0
        var offendingLines: [String] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            scannedFileCount += 1
            let isTheOutput = fileURL.lastPathComponent == "StandardStreamOutput.swift"
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            for (lineIndex, line) in contents.components(separatedBy: .newlines).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else { continue }
                let writesThroughFileHandle = code.contains("FileHandle.standardOutput") || code.contains("FileHandle.standardError")
                let writesDirectly = Self.containsBareCall(to: "print", in: code)
                    || Self.containsBareCall(to: "fputs", in: code)
                    || Self.containsBareCall(to: "fwrite", in: code)
                if writesThroughFileHandle || (writesDirectly && !isTheOutput) {
                    offendingLines.append("\(fileURL.lastPathComponent):\(lineIndex + 1): \(code)")
                }
            }
        }
        #expect(scannedFileCount > 20, "the premise: the scan sees the command-line sources")
        #expect(offendingLines.isEmpty, "\(offendingLines.joined(separator: "\n"))")
    }

    @Test("The scan's call detector discriminates")
    func callDetectorDiscriminates() {
        #expect(Self.containsBareCall(to: "print", in: "print(text)"))
        #expect(Self.containsBareCall(to: "fputs", in: "_ = fputs(line, stderr)"))
        #expect(!Self.containsBareCall(to: "print", in: "builder.printRoot()"))
        #expect(!Self.containsBareCall(to: "print", in: "node.print(using: options)"))
    }

    /// Is `name(` called as a function, rather than as a member of something?
    private static func containsBareCall(to name: String, in code: String) -> Bool {
        var searchRange = code.startIndex ..< code.endIndex
        while let found = code.range(of: name + "(", range: searchRange) {
            if found.lowerBound == code.startIndex { return true }
            let preceding = code[code.index(before: found.lowerBound)]
            if !preceding.isLetter, !preceding.isNumber, preceding != ".", preceding != "_" {
                return true
            }
            searchRange = found.upperBound ..< code.endIndex
        }
        return false
    }
}
