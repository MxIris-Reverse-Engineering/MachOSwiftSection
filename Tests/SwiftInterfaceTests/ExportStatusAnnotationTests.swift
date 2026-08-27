import Foundation
import Testing
import MachOKit
@_spi(Internals) @testable import MachOSymbols
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftPrinting
@_spi(Support) @testable import SwiftInterface
@testable import MachOTestingSupport
import MachOFixtureSupport

/// End-to-end coverage for the `// not exported` annotation (evolution
/// proposal 0008) on the `SymbolTestsCore` fixture — a library-evolution
/// Release build, which is exactly the shape where the naive
/// implementation went wrong three separate ways, each pinned here:
///
/// - a `public` member's implementation symbol is trie-absent while its
///   `Tj` dispatch thunk is exported (external callers dispatch through
///   the thunk), so the bare-name query flagged EVERY public member;
/// - an `override` links through the PARENT's dispatch thunk and owns no
///   exported symbol, so it must be exempt, not flagged;
/// - an `@objc` member dispatches through objc_msgSend and needs no Swift
///   symbol, so it must be exempt too.
@Suite(.serialized)
final class ExportStatusAnnotationTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    private func buildOutput(printExportStatus: Bool) async throws -> String {
        var printConfiguration = SwiftDeclarationPrintConfiguration()
        printConfiguration.printExportStatus = printExportStatus
        let configuration = SwiftInterfaceBuilderConfiguration(
            indexConfiguration: .init(showCImportedTypes: false),
            printConfiguration: printConfiguration
        )
        let unsafeMachOFile = machOFile
        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [], in: unsafeMachOFile)
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    /// Whether the line immediately preceding the first line containing
    /// `declaration` is a `not exported` comment.
    private func isAnnotated(_ declaration: String, in output: String) throws -> Bool {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        let index = try #require(lines.firstIndex { $0.contains(declaration) }, "declaration not found: \(declaration)")
        guard index > 0 else { return false }
        return lines[index - 1].contains("// not exported")
    }

    /// A `public` member whose implementation symbol is trie-absent but
    /// whose `Tj` thunk is exported must NOT be annotated — the regression
    /// that motivated `isExportedIncludingDerivedSymbols`. The premise is
    /// asserted through the store first, so the negative expectation cannot
    /// pass vacuously (e.g. with the whole feature disabled but the member
    /// coincidentally exported).
    @Test func publicThunkExportedMemberIsNotAnnotated() async throws {
        let unsafeMachOFile = machOFile
        let implementationName = "_$s15SymbolTestsCore6ActorsO9ActorTestC11mutateStateyyF"
        #expect(SymbolIndexStore.shared.isExported(name: implementationName, in: unsafeMachOFile) == false)
        #expect(SymbolIndexStore.shared.isExportedIncludingDerivedSymbols(name: implementationName, in: unsafeMachOFile) == true)

        let output = try await buildOutput(printExportStatus: true)
        #expect(try !isAnnotated("func mutateState()", in: output))
    }

    /// `@objc dynamic` members dispatch through objc_msgSend; their Swift
    /// symbols are legitimately absent from the trie, and the `@objc`
    /// exemption keeps them unannotated. The premise — EVERY form of the
    /// member trie-misses — is asserted first: only then is "not annotated"
    /// necessarily the exemption's doing rather than fixture luck.
    @Test func objcMemberIsExempt() async throws {
        let unsafeMachOFile = machOFile
        let implementationName = "_$s15SymbolTestsCore10AttributesO18ObjCAttributeClassC17objcDynamicMethodyyF"
        #expect(SymbolIndexStore.shared.isExportedIncludingDerivedSymbols(name: implementationName, in: unsafeMachOFile) == false)

        let output = try await buildOutput(printExportStatus: true)
        #expect(try !isAnnotated("@objc func objcDynamicMethod()", in: output))
    }

    /// `override` members link through the parent's dispatch thunk and own
    /// no exported symbol; the override exemption keeps them unannotated.
    /// Same premise discipline as the `@objc` test above.
    @Test func overrideMemberIsExempt() async throws {
        let unsafeMachOFile = machOFile
        let implementationName = "_$s15SymbolTestsCore7ClassesO25ExternalSwiftSubclassTestC14instanceMethodSSyF"
        #expect(SymbolIndexStore.shared.isExportedIncludingDerivedSymbols(name: implementationName, in: unsafeMachOFile) == false)

        let output = try await buildOutput(printExportStatus: true)
        #expect(try !isAnnotated("override func instanceMethod() -> Swift.String", in: output))
    }

    /// The true positive: `GenericAsyncSequenceTest.AsyncIterator` declares
    /// no initializer, so its implicit `init()` is `internal` — no form of
    /// it reaches the trie, and the annotation states that fact.
    /// (`Classes.ClassTest` would be the more obvious specimen, but its
    /// unreferenced implicit init emits no implementation symbol at all,
    /// so the interface never renders it.) The assertion is scoped to the
    /// `AsyncIterator` block and matches the exact trimmed line, so member
    /// reordering or a stray substring elsewhere cannot silently redirect
    /// it onto a different declaration.
    @Test func internalSynthesizedInitIsAnnotated() async throws {
        let output = try await buildOutput(printExportStatus: true)
        let typeBlock = try #require(output.range(of: "struct GenericAsyncSequenceTest"))
        let iteratorBlock = try #require(output.range(of: "struct AsyncIterator {", range: typeBlock.upperBound ..< output.endIndex))
        let lines = output[iteratorBlock.upperBound...].split(separator: "\n", omittingEmptySubsequences: false)
        // The block's closing brace at the same indent bounds the search.
        let closingIndex = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces) == "}" } ?? lines.endIndex
        let initIndex = try #require(
            lines[..<closingIndex].firstIndex { $0.trimmingCharacters(in: .whitespaces) == "init()" },
            "AsyncIterator block should render its implicit init()"
        )
        #expect(initIndex > lines.startIndex && lines[initIndex - 1].contains("// not exported"))
    }

    /// Flag off (the default): output is byte-free of the annotation.
    @Test func defaultOutputCarriesNoAnnotation() async throws {
        let output = try await buildOutput(printExportStatus: false)
        #expect(!output.contains("// not exported"))
    }

    /// The comment must sit on the line IMMEDIATELY above the declaration it
    /// annotates — for TOP-LEVEL globals as well as members. Every other test
    /// in this suite reads a member, whose `Rows(level:)` renderer keeps the
    /// pair adjacent; the globals blocks go through
    /// `SwiftDeclarationPrinter.globalExportStatusComment`, which used to emit
    /// its own trailing `BreakLine()` inside a `BlockList` that already
    /// contributes one leading break per item — so every global's comment
    /// floated a blank line above its declaration and read as annotating the
    /// PREVIOUS one.
    @Test func exportStatusCommentIsAdjacentToItsDeclaration() async throws {
        let output = try await buildOutput(printExportStatus: true)
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)

        var annotatedGlobalCount = 0
        for (index, line) in lines.enumerated() where line.contains("// not exported") {
            let following = index + 1 < lines.count ? lines[index + 1] : ""
            #expect(
                !following.trimmingCharacters(in: .whitespaces).isEmpty,
                "blank line between the export-status comment and its declaration at line \(index + 1)"
            )
            // A comment at column 0 belongs to a top-level global.
            if line.hasPrefix("// not exported") { annotatedGlobalCount += 1 }
        }

        // Non-vacuity: the member path was already adjacent before the fix, so
        // the assertion above only means something if the fixture actually
        // annotates a GLOBAL.
        #expect(annotatedGlobalCount > 0, "fixture annotates no top-level global; the adjacency check would be vacuous")
    }
}
