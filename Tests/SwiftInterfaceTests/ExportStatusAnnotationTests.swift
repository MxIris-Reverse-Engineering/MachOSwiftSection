import Foundation
import Testing
import MachOKit
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
    /// that motivated `isExportedIncludingDerivedSymbols`.
    @Test func publicThunkExportedMemberIsNotAnnotated() async throws {
        let output = try await buildOutput(printExportStatus: true)
        #expect(try !isAnnotated("func mutateState()", in: output))
    }

    /// `@objc dynamic` members dispatch through objc_msgSend; their Swift
    /// symbols are legitimately absent from the trie, and the `@objc`
    /// exemption keeps them unannotated.
    @Test func objcMemberIsExempt() async throws {
        let output = try await buildOutput(printExportStatus: true)
        #expect(try !isAnnotated("@objc func objcDynamicMethod()", in: output))
    }

    /// `override` members link through the parent's dispatch thunk and own
    /// no exported symbol; the override exemption keeps them unannotated.
    @Test func overrideMemberIsExempt() async throws {
        let output = try await buildOutput(printExportStatus: true)
        #expect(try !isAnnotated("override func instanceMethod() -> Swift.String", in: output))
    }

    /// The true positive: `GenericAsyncSequenceTest.AsyncIterator` declares
    /// no initializer, so its implicit `init()` is `internal` — no form of
    /// it reaches the trie, and the annotation states that fact.
    /// (`Classes.ClassTest` would be the more obvious specimen, but its
    /// unreferenced implicit init emits no implementation symbol at all,
    /// so the interface never renders it.)
    @Test func internalSynthesizedInitIsAnnotated() async throws {
        let output = try await buildOutput(printExportStatus: true)
        let typeBlock = try #require(output.range(of: "struct GenericAsyncSequenceTest"))
        let blockTail = String(output[typeBlock.lowerBound...])
        #expect(try isAnnotated("init()", in: blockTail))
    }

    /// Flag off (the default): output is byte-free of the annotation.
    @Test func defaultOutputCarriesNoAnnotation() async throws {
        let output = try await buildOutput(printExportStatus: false)
        #expect(!output.contains("// not exported"))
    }
}
