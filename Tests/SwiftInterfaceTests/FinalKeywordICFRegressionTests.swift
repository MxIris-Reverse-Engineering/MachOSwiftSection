@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Support) @testable import SwiftPrinting
import Foundation
import Testing
import MachOKit
@_spi(Support) @testable import SwiftInterface
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Regression coverage for the identical-code-folding false positive in the
/// `final` recovery (evolution proposal 0006), pinned against Xcode's real
/// `SourceEditor.framework` — the binary issue #106 was reported against.
///
/// SourceEditor folds 1128 empty implementations onto one address
/// (`SourceEditorView.elide` among them), where the
/// descriptor→implementation-symbol join cannot pair descriptors with
/// members. Every folded member used to read as `final` even though its `Tq`
/// method-descriptor symbol proves a vtable entry exists. The `Tq` negative
/// evidence gate is what this suite pins.
///
/// Environment-gated: skipped on machines without Xcode's SourceEditor.
@Suite(.serialized, .enabled(if: FileManager.default.fileExists(atPath: MachOFileName.SourceEditorFromXcode.rawValue)))
final class FinalKeywordICFRegressionTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SourceEditorFromXcode }

    @Test func icfFoldedMembersWithDescriptorSymbolsAreNotFinal() async throws {
        let unsafeMachOFile = machOFile
        let builder = try SwiftInterfaceBuilder(configuration: .init(indexConfiguration: .init(showCImportedTypes: false)), eventHandlers: [], in: unsafeMachOFile)
        try await builder.prepare()
        let output = try await builder.printRoot().string

        // `SourceEditorView.elide` / `didScrollPositionToVisible` are folded
        // onto the shared empty implementation, but both carry exported `Tq`
        // method-descriptor symbols (and `Tj` dispatch thunks) — provably
        // non-final, whatever the address join says.
        #expect(output.contains("func elide"))
        #expect(!output.contains("final func elide"))
        #expect(!output.contains("final func didScrollPositionToVisible"))

        // Positive control, straight from issue #106: the getter of
        // `SourceEditorDataSource.languageService` exports only a direct
        // symbol (no `Tq`, no thunk) — a genuine `final`, and its lazy
        // storage's `Optional` must not leak into the printed type.
        #expect(output.contains("final lazy var languageService: SourceEditor.SourceEditorLanguageService\n"))
        #expect(!output.contains("languageService: SourceEditor.SourceEditorLanguageService?"))
    }
}
