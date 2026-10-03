import Foundation
import Rainbow
import Semantic
import SwiftDeclaration
import SwiftIndexing
import SwiftSectionKit

/// Writes a request's output where `swift-section` has always written it: the
/// product to stdout, diagnostics to stderr — except the severities a command
/// lists in `standardOutputSeverities`.
///
/// Every write goes through `fwrite`, never `FileHandle.write(_:)`: that
/// overload is the Objective-C bridge and raises an exception Swift cannot
/// catch when the stream is closed, which aborted the process instead of
/// dropping the line.
///
/// `@unchecked Sendable`: the two `FILE` pointers are only ever passed to
/// stdio, whose calls lock the stream themselves.
struct StandardStreamOutput: SwiftSectionOutput, @unchecked Sendable {
    var colorScheme: SemanticColorScheme = .none
    /// `interface` prints its progress lines on stdout and `dump` its
    /// per-declaration errors. Both are historical, kept so that the output
    /// stays byte-identical (evolution proposal `swift-section-kit`, follow-up
    /// work).
    var standardOutputSeverities: Set<SwiftSectionDiagnostic.Severity> = []
    var standardOutput: UnsafeMutablePointer<FILE> = stdout
    var standardError: UnsafeMutablePointer<FILE> = stderr

    func write(_ product: SwiftSectionProduct) {
        switch product {
        case .declarations(let semanticString):
            writeLine(semanticString.colorized(using: colorScheme), to: standardOutput)
        case .text(let text):
            writeLine(text, to: standardOutput)
        case .annotatedInterface(let text, let style):
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (line, lineKind) in zip(lines, style.lineKinds(of: text)) {
                writeLine(String(line).colorized(as: lineKind), to: standardOutput)
            }
        case .data(let data):
            data.withUnsafeBytes { buffer in
                _ = fwrite(buffer.baseAddress, 1, buffer.count, standardOutput)
            }
            writeLine("", to: standardOutput)
        }
    }

    func report(_ diagnostic: SwiftSectionDiagnostic) {
        if standardOutputSeverities.contains(diagnostic.severity) {
            // `dump`'s error lines have always been red, whatever the color
            // scheme.
            writeLine(diagnostic.severity == .error ? diagnostic.message.red : diagnostic.message, to: standardOutput)
        } else {
            writeLine(diagnostic.message, to: standardError)
        }
    }

    func indexEventHandlers(forInputLabeled label: String?) -> [any SwiftIndexEvents.Handler] {
        [ConsoleEventHandler(label: label)]
    }

    /// `text` and a newline, byte for byte — `fputs` would stop at an
    /// embedded NUL where `print` does not.
    private func writeLine(_ text: String, to stream: UnsafeMutablePointer<FILE>) {
        var bytes = Array(text.utf8)
        bytes.append(UInt8(ascii: "\n"))
        bytes.withUnsafeBufferPointer { buffer in
            _ = fwrite(buffer.baseAddress, 1, buffer.count, stream)
        }
    }
}

extension SemanticString {
    func colorized(using colorScheme: SemanticColorScheme) -> String {
        components.map { $0.string.withColor(for: $0.type, colorScheme: colorScheme) }.joined()
    }
}

extension String {
    func colorized(as lineKind: AnnotatedLineKind) -> String {
        switch lineKind {
        case .header:
            cyan
        case .added:
            green
        case .removed:
            red
        case .modified:
            yellow
        case .plain:
            self
        }
    }

    func withColorHex(for type: SemanticType, colorScheme: SemanticColorScheme) -> String? {
        switch colorScheme {
        case .none:
            return nil
        case .light:
            switch type {
            case .comment:
                return "#56606B"
            case .keyword:
                return "#C33381"
            case .type(_, .name):
                return "#2E0D6E"
            case .type(_, .declaration):
                return "#004975"
            case .function(.name),
                 .member(.name):
                return "#5C2699"
            case .function(.declaration),
                 .member(.declaration),
                 .variable:
                return "#0F68A0"
            case .numeric:
                return "#000BFF"
            default:
                return nil
            }
        case .dark:
            switch type {
            case .comment:
                return "#6C7987"
            case .keyword:
                return "#F2248C"
            case .type(_, .name):
                return "#D0A8FF"
            case .type(_, .declaration):
                return "#5DD8FF"
            case .function(.name),
                 .member(.name):
                return "#A167E6"
            case .function(.declaration),
                 .member(.declaration):
                return "#41A1C0"
            case .numeric:
                return "#D0BF69"
            default:
                return nil
            }
        }
    }

    func withColor(for type: SemanticType, colorScheme: SemanticColorScheme) -> String {
        if let colorHex = withColorHex(for: type, colorScheme: colorScheme) {
            hex(colorHex, to: .bit24)
        } else if type == .error {
            red
        } else {
            self
        }
    }
}
