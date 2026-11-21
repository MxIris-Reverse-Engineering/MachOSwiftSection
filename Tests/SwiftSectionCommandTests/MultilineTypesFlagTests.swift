import Foundation
import Testing
import ArgumentParser
import SwiftSectionKit
import SwiftDeclarationRendering
@testable import swift_section

/// `--multiline-types` and `--maximum-line-width` on `dump` and `interface`
/// (evolution proposal `multiline-type-formatting`): off by default, mapped
/// onto the request's `multilineTypeFormatting`, and a width without the flag
/// or below one column is a usage error, exit code 64.
@Suite
struct MultilineTypesFlagTests {
    @Test func formattingIsOffByDefault() throws {
        #expect(try DumpCommand.parse(["/tmp/example"]).makeRequest().multilineTypeFormatting == nil)
        #expect(try InterfaceCommand.parse(["/tmp/example"]).makeRequest().multilineTypeFormatting == nil)
    }

    @Test func multilineTypesFlagMapsOntoTheRequest() throws {
        #expect(try DumpCommand.parse(["/tmp/example", "--multiline-types"]).makeRequest().multilineTypeFormatting == MultilineTypeFormatting())
        #expect(try InterfaceCommand.parse(["/tmp/example", "--multiline-types"]).makeRequest().multilineTypeFormatting == MultilineTypeFormatting())
    }

    @Test func maximumLineWidthMapsOntoTheRequest() throws {
        let arguments = ["/tmp/example", "--multiline-types", "--maximum-line-width", "120"]
        #expect(try DumpCommand.parse(arguments).makeRequest().multilineTypeFormatting == MultilineTypeFormatting(maximumLineWidth: 120))
        #expect(try InterfaceCommand.parse(arguments).makeRequest().multilineTypeFormatting == MultilineTypeFormatting(maximumLineWidth: 120))
    }

    @Test(arguments: [
        (["/tmp/example", "--maximum-line-width", "120"], "--maximum-line-width needs --multiline-types"),
        (["/tmp/example", "--multiline-types", "--maximum-line-width", "0"], "--maximum-line-width must be a positive number of columns"),
    ])
    func usageMistakesAreValidationErrors(arguments: [String], messagePart: String) {
        #expect(
            performing: {
                _ = try DumpCommand.parse(arguments)
            },
            throws: { error in
                DumpCommand.message(for: error).contains(messagePart) && DumpCommand.exitCode(for: error) == ExitCode(64)
            }
        )
        #expect(
            performing: {
                _ = try InterfaceCommand.parse(arguments)
            },
            throws: { error in
                InterfaceCommand.message(for: error).contains(messagePart) && InterfaceCommand.exitCode(for: error) == ExitCode(64)
            }
        )
    }

    @Test func helpNamesTheDefaultWidth() {
        for helpMessage in [DumpCommand.helpMessage(columns: 1000), InterfaceCommand.helpMessage(columns: 1000)] {
            #expect(helpMessage.contains("--maximum-line-width <columns>"))
            #expect(helpMessage.contains("--multiline-types breaks its types. (default: 100)"))
        }
    }
}
