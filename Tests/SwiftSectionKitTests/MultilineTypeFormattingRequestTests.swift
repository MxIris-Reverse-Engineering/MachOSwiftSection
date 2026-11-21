import Foundation
import Testing
import SwiftSectionKit
import SwiftDeclarationRendering
import Semantic

/// `multilineTypeFormatting` on the `dump` and `interface` requests
/// (evolution proposal `multiline-type-formatting`): with it, the product is
/// exactly what formatting the product printed without it gives — the whole
/// interface at once, the dump one declaration at a time — and without it
/// nothing changes.
@Suite
struct MultilineTypeFormattingRequestTests {
    private static let fixture = MachOSource.file(path: FixtureFiles.symbolTestsCore, architecture: nil)

    /// Narrow enough that the fixture's long generic field types break.
    private static let formatting = MultilineTypeFormatting(maximumLineWidth: 30)

    /// A field the formatting breaks, as printed on one line.
    private static let oneLineField = "var nested: SymbolTestsCore.GenericFieldLayout.Pair<SymbolTestsCore.GenericFieldLayout.Box<Swift.Int>, Swift.Int>"

    private static func declarations(of output: RecordingOutput) -> [SemanticString] {
        output.products.compactMap { product in
            if case .declarations(let semanticString) = product { semanticString } else { nil }
        }
    }

    @Test func requestsFormatNothingUnlessAsked() {
        #expect(InterfaceRequest(source: Self.fixture).multilineTypeFormatting == nil)
        #expect(DumpRequest(source: Self.fixture).multilineTypeFormatting == nil)
    }

    @Test func interfaceRequestFormatsLongTypesWhenAsked() async throws {
        let plain = RecordingOutput()
        try await InterfaceRequest(source: Self.fixture).run(output: plain, environment: .testing)
        let formatted = RecordingOutput()
        try await InterfaceRequest(source: Self.fixture, multilineTypeFormatting: Self.formatting).run(output: formatted, environment: .testing)

        let plainInterface = try #require(Self.declarations(of: plain).only)
        let formattedInterface = try #require(Self.declarations(of: formatted).only)
        #expect(plainInterface.string.contains(Self.oneLineField))
        #expect(!formattedInterface.string.contains(Self.oneLineField))
        #expect(formattedInterface.components == Self.formatting.format(plainInterface).components)
    }

    @Test func interfaceWrittenToFileIsFormattedToo() async throws {
        let directoryURL = try FixtureFiles.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let interfacePath = directoryURL.appendingPathComponent("interface.swift").path

        let printed = RecordingOutput()
        try await InterfaceRequest(source: Self.fixture, multilineTypeFormatting: Self.formatting).run(output: printed, environment: .testing)
        try await InterfaceRequest(source: Self.fixture, multilineTypeFormatting: Self.formatting, destination: .file(path: interfacePath)).run(output: RecordingOutput(), environment: .testing)

        let printedInterface = try #require(Self.declarations(of: printed).only)
        #expect(!printedInterface.string.contains(Self.oneLineField))
        #expect(try String(contentsOfFile: interfacePath, encoding: .utf8) == printedInterface.string)
    }

    @Test func dumpRequestFormatsEachDeclarationWhenAsked() async throws {
        let plain = RecordingOutput()
        try await DumpRequest(source: Self.fixture, sections: .only([.types])).run(output: plain, environment: .testing)
        let formatted = RecordingOutput()
        try await DumpRequest(source: Self.fixture, sections: .only([.types]), multilineTypeFormatting: Self.formatting).run(output: formatted, environment: .testing)

        let plainDeclarations = Self.declarations(of: plain)
        let formattedDeclarations = Self.declarations(of: formatted)
        #expect(plainDeclarations.count == formattedDeclarations.count)
        #expect(plainDeclarations.contains { $0.string.contains(Self.oneLineField) })
        #expect(!formattedDeclarations.contains { $0.string.contains(Self.oneLineField) })
        for (plainDeclaration, formattedDeclaration) in zip(plainDeclarations, formattedDeclarations) {
            #expect(formattedDeclaration.components == Self.formatting.format(plainDeclaration).components)
        }
    }
}

extension Collection {
    /// The collection's single element; `nil` when it has none or several.
    fileprivate var only: Element? {
        count == 1 ? first : nil
    }
}
