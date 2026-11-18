import Foundation
import Testing
import ArgumentParser
import SwiftSectionKit
@testable import swift_section

/// `refs` and `symbolicate`: the flags each reaches in the request, and the
/// combinations the command line refuses.
@Suite
struct CrossReferenceCommandTests {
    @Test func refsRequiresExactlyOneQuery() {
        #expect(throws: (any Error).self) { try ReferencesCommand.parse(["--uses-system-dyld-shared-cache"]) }
        #expect(throws: (any Error).self) { try ReferencesCommand.parse(["--uses-system-dyld-shared-cache", "--selector", "init", "--string", "init"]) }
    }

    @Test("refs needs exactly one input", arguments: [
        ["--selector", "init"],
        ["/tmp/Sample", "--uses-system-dyld-shared-cache", "--selector", "init"],
        ["--dyld-shared-cache", "/tmp/cache", "--uses-system-dyld-shared-cache", "--selector", "init"],
    ])
    func refsRequiresExactlyOneInput(arguments: [String]) {
        #expect(throws: (any Error).self) { try ReferencesCommand.parse(arguments) }
    }

    @Test func refsMapsItsFlagsOntoTheRequest() throws {
        let request = try ReferencesCommand.parse([
            "--selector", "makeKeyAndOrderFront:", "--dyld-shared-cache", "/tmp/cache",
            "--in-image", "AppKit", "--in-image", "Foundation", "--limit", "5", "--json",
        ]).makeRequest()
        #expect(request == ReferencesRequest(
            input: .dyldSharedCache(path: "/tmp/cache"),
            subject: .selector("makeKeyAndOrderFront:"),
            imageNames: ["AppKit", "Foundation"],
            limit: 5,
            format: .json
        ))
    }

    @Test func refsReadsFilesWithAnArchitecture() throws {
        let request = try ReferencesCommand.parse(["/tmp/Foo", "/tmp/Bar.dylib", "-a", "arm64e", "--string", "Hello"]).makeRequest()
        #expect(request.input == .files(paths: ["/tmp/Foo", "/tmp/Bar.dylib"], architecture: .arm64e))
        #expect(request.subject == .string("Hello"))
        #expect(request.format == .text)
    }

    @Test("Each query flag reaches its subject", arguments: [
        (["--symbol", "_objc_msgSend"], CrossReferenceSubject.symbol("_objc_msgSend")),
        (["--class", "NSWindow"], .objectiveCClass("NSWindow")),
        (["--function", "0x1880a1000"], .function(address: 0x1_880A_1000, imageName: nil)),
        (["--function", "4096", "--function-image", "Foo"], .function(address: 4096, imageName: "Foo")),
        (["--ivar", "NSWindow._frame"], .instanceVariable(className: "NSWindow", name: "_frame")),
        (["--string", "NSWindowDidBecomeKeyNotification"], .string("NSWindowDidBecomeKeyNotification")),
    ])
    func refsMapsEachQuery(arguments: [String], subject: CrossReferenceSubject) throws {
        let request = try ReferencesCommand.parse(arguments + ["--uses-system-dyld-shared-cache"]).makeRequest()
        #expect(request.subject == subject)
        #expect(request.input == .systemDyldSharedCache)
        #expect(request.direction == .callers)
    }

    @Test func refsCalleesFollowAFunction() throws {
        let request = try ReferencesCommand.parse(["--function", "0x10", "--callees", "--uses-system-dyld-shared-cache"]).makeRequest()
        #expect(request.direction == .callees)
    }

    @Test("refs refuses flags that need another one", arguments: [
        ["--selector", "init", "--callees"],
        ["--selector", "init", "--function-image", "Foo"],
        ["--ivar", "NoDot"],
        ["--ivar", "Trailing."],
        ["--function", "nowhere"],
        ["--selector", "init", "--limit", "0"],
    ])
    func refsRefusesIncompleteFlags(arguments: [String]) {
        #expect(throws: (any Error).self) { try ReferencesCommand.parse(arguments + ["--uses-system-dyld-shared-cache"]) }
    }

    @Test func symbolicateMapsItsFlagsOntoTheRequest() throws {
        let request = try SymbolicateCommand.parse(["0x10", "42", "--file", "/tmp/Foo", "--file", "/tmp/Bar.dylib", "--in-image", "Bar.dylib", "--json"]).makeRequest()
        #expect(request == SymbolicateRequest(
            input: .files(paths: ["/tmp/Foo", "/tmp/Bar.dylib"], architecture: nil),
            addresses: [0x10, 42],
            imageName: "Bar.dylib",
            format: .json
        ))
    }

    @Test("symbolicate refuses what it cannot read", arguments: [
        ["--uses-system-dyld-shared-cache"],
        ["zz", "--uses-system-dyld-shared-cache"],
        ["0x10"],
        ["0x10", "--uses-system-dyld-shared-cache", "--in-image", "A", "--in-image", "B"],
    ])
    func symbolicateRefusesBadInput(arguments: [String]) {
        #expect(throws: (any Error).self) { try SymbolicateCommand.parse(arguments) }
    }

    /// Naming a missing image is a usage mistake: exit code 64, the flags
    /// named.
    @Test func crossReferenceUsageErrorsBecomeValidationErrors() {
        let missingImage = CommandLineErrorTranslation.translated(CrossReferenceRequestError.imageNotFound(name: "Nowhere"))
        #expect((missingImage as? ValidationError)?.message.contains("--in-image") == true)
        let ambiguous = CommandLineErrorTranslation.translated(CrossReferenceRequestError.ambiguousFunction(address: 0x10, imagePaths: ["/tmp/A", "/tmp/B"]))
        #expect((ambiguous as? ValidationError)?.message.contains("--function-image") == true)
        #expect(CommandLineErrorTranslation.translated(CrossReferenceRequestError.noFunction(address: 0x10)) is CrossReferenceRequestError)
    }
}
