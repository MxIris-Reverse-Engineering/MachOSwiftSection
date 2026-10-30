import Foundation
import Testing
import MachOKit
import Semantic
@_spi(Internals) @testable import MachOSymbols
@testable import MachOSwiftSection
import SwiftDeclaration
@_spi(Support) import SwiftIndexing
@_spi(Support) @testable import SwiftPrinting
@_spi(Support) @testable import SwiftInterface
import MachOTestingSupport

/// The exported-only filter (evolution proposal
/// `exported-only-interface`) over `internal` declarations, on the
/// on-the-fly `ExportedOnlyFixture` module (see its documentation for the
/// shapes it carries and why `SymbolTestsCore` cannot pin them).
@Suite(.serialized)
struct ExportedOnlyLibraryEvolutionFixtureTests {
    private func makePreparedBuilder(exportedOnly: Bool, showsCImportedTypes: Bool = false) async throws -> SwiftInterfaceBuilder<MachOFile> {
        let machOFile = try ExportedOnlyFixture.machOFile()
        var printConfiguration = SwiftDeclarationPrintConfiguration()
        printConfiguration.printExportedDeclarationsOnly = exportedOnly
        let builder = try SwiftInterfaceBuilder(
            configuration: .init(indexConfiguration: .init(showCImportedTypes: showsCImportedTypes), printConfiguration: printConfiguration),
            eventHandlers: [],
            in: machOFile
        )
        try await builder.prepare()
        return builder
    }

    private func buildOutput(exportedOnly: Bool, showsCImportedTypes: Bool = false) async throws -> (output: String, machOFile: MachOFile) {
        let builder = try await makePreparedBuilder(exportedOnly: exportedOnly, showsCImportedTypes: showsCImportedTypes)
        return (try await builder.printRoot().string, builder.machO)
    }

    /// The premise every assertion below rests on: without `-enable-testing`
    /// the internal descriptors are local symbols and the public ones are
    /// in the trie — the store must answer `false` / `true`, never `nil`.
    @Test func fixtureExportsExactlyItsPublicDescriptors() async throws {
        let (_, machOFile) = try await buildOutput(exportedOnly: false)
        #expect(SymbolIndexStore.shared.isExported(name: "_$s19ExportedOnlyFixture11PublicShapeVMn", in: machOFile) == true)
        #expect(SymbolIndexStore.shared.isExported(name: "_$s19ExportedOnlyFixture13InternalShapeVMn", in: machOFile) == false)
        #expect(SymbolIndexStore.shared.isExported(name: "_$s19ExportedOnlyFixture14PublicContractMp", in: machOFile) == true)
        #expect(SymbolIndexStore.shared.isExported(name: "_$s19ExportedOnlyFixture16InternalContractMp", in: machOFile) == false)
    }

    @Test func internalTypesAreDroppedAtEveryNestingLevel() async throws {
        let (defaultOutput, _) = try await buildOutput(exportedOnly: false)
        #expect(defaultOutput.contains("struct InternalShape {"))
        #expect(defaultOutput.contains("struct InternalNested {"))

        let (filteredOutput, _) = try await buildOutput(exportedOnly: true)
        #expect(filteredOutput.contains("struct PublicShape {"))
        #expect(filteredOutput.contains("struct PublicNested {"))
        #expect(!filteredOutput.contains("struct InternalShape {"))
        #expect(!filteredOutput.contains("struct InternalNested {"))
        // The internal type's extension goes with its target.
        #expect(!filteredOutput.contains("extension ExportedOnlyFixture.InternalShape"))
        #expect(!filteredOutput.contains("orphanMethod"))
    }

    @Test func internalProtocolItsDefaultsAndConformancesToItAreDropped() async throws {
        let (defaultOutput, _) = try await buildOutput(exportedOnly: false)
        #expect(defaultOutput.contains("protocol InternalContract {"))
        #expect(defaultOutput.contains("extension ExportedOnlyFixture.PublicShape: ExportedOnlyFixture.InternalContract"))

        let (filteredOutput, _) = try await buildOutput(exportedOnly: true)
        #expect(filteredOutput.contains("protocol PublicContract {"))
        #expect(filteredOutput.contains("extension ExportedOnlyFixture.PublicShape: ExportedOnlyFixture.PublicContract"))
        #expect(filteredOutput.contains("func requirement()"))
        #expect(!filteredOutput.contains("protocol InternalContract {"))
        #expect(!filteredOutput.contains("hiddenDefault"))
        // A PUBLIC type's conformance to an INTERNAL protocol: the target is
        // exported, the conforming protocol is not — the extension goes.
        #expect(!filteredOutput.contains("extension ExportedOnlyFixture.PublicShape: ExportedOnlyFixture.InternalContract"))
        #expect(!filteredOutput.contains("func hidden()"))
    }

    /// Members and STORED properties of a kept type: the internal method and
    /// the internal stored `var` (whose accessor group joined as local
    /// symbols) go, the public ones stay.
    @Test func internalMembersAndStoredPropertiesAreDropped() async throws {
        let (defaultOutput, _) = try await buildOutput(exportedOnly: false)
        #expect(defaultOutput.contains("var internalNote: Swift.String"))
        #expect(defaultOutput.contains("func internalMethod()"))

        let (filteredOutput, _) = try await buildOutput(exportedOnly: true)
        #expect(filteredOutput.contains("var title: Swift.String"))
        #expect(filteredOutput.contains("func publicMethod()"))
        #expect(filteredOutput.contains("init(title: Swift.String, internalNote: Swift.String)"))
        #expect(!filteredOutput.contains("var internalNote"))
        #expect(!filteredOutput.contains("func internalMethod()"))
    }

    /// Constrained-extension members render inside ONE plain
    /// `extension Foo { … }` container per type, each member carrying its
    /// own `where` clause. `PublicPair`'s container holds only an internal
    /// member: the filter EMPTIES it and, being a plain extension, the whole
    /// block goes. `PublicBox`'s container keeps its public member and loses
    /// the internal one.
    @Test func emptiedPlainExtensionIsDroppedAndPopulatedOneKept() async throws {
        let (defaultOutput, _) = try await buildOutput(exportedOnly: false)
        #expect(defaultOutput.contains("extension ExportedOnlyFixture.PublicPair {"))
        #expect(defaultOutput.contains("func internalOnlyConstrainedMember() where A == Swift.Int"))
        #expect(defaultOutput.contains("func internalConstrainedMember() where A == Swift.Int"))

        let (filteredOutput, _) = try await buildOutput(exportedOnly: true)
        #expect(filteredOutput.contains("struct PublicPair<A> {"))
        #expect(!filteredOutput.contains("extension ExportedOnlyFixture.PublicPair"))
        #expect(!filteredOutput.contains("internalOnlyConstrainedMember"))
        #expect(filteredOutput.contains("extension ExportedOnlyFixture.PublicBox {"))
        #expect(filteredOutput.contains("func publicConstrainedMember() where A == Swift.String"))
        #expect(!filteredOutput.contains("internalConstrainedMember"))
    }

    /// Globals follow the member rule; enum cases own no symbols and are
    /// never touched.
    @Test func internalGlobalIsDroppedAndEnumCasesAreKept() async throws {
        let (defaultOutput, _) = try await buildOutput(exportedOnly: false)
        #expect(defaultOutput.contains("func internalGlobal()"))

        let (filteredOutput, _) = try await buildOutput(exportedOnly: true)
        #expect(filteredOutput.contains("func publicGlobal()"))
        #expect(!filteredOutput.contains("func internalGlobal()"))
        #expect(filteredOutput.contains("case alpha"))
        #expect(filteredOutput.contains("case beta"))
    }

    /// A C-imported type's descriptor is a copy each module using the type
    /// emits for itself, under non-unique linkage, so no image exports it
    /// and it says nothing about whether the type can be used from outside
    /// (evolution proposal `exported-only-marking-mode`). Read as "not
    /// exported", it put the type into the filter's scope once
    /// `showCImportedTypes` indexed it, and the filter dropped the type along
    /// with this image's public extension of it and its public conformance.
    @Test func cImportedTypeIsNotRuledOnAndItsPublicExtensionsAreKept() async throws {
        let builder = try await makePreparedBuilder(exportedOnly: true, showsCImportedTypes: true)
        let cImportedTypeDefinition = try #require(builder.indexer.allTypeDefinitions.values.first { $0.typeName.name.hasSuffix("CGPoint") })
        #expect(!cImportedTypeDefinition.exportStatus.isDefinitelyNotExported)
        #expect(cImportedTypeDefinition.exportStatus == .declarationIsCImported)

        let (defaultOutput, _) = try await buildOutput(exportedOnly: false, showsCImportedTypes: true)
        #expect(defaultOutput.contains("struct CGPoint {"))
        #expect(defaultOutput.contains("CGPoint: ExportedOnlyFixture.PublicContract {"))
        #expect(defaultOutput.contains("func publicCImportedTypeMember()"))

        let filteredOutput = try await builder.printRoot().string
        #expect(filteredOutput.contains("struct CGPoint {"))
        #expect(filteredOutput.contains("CGPoint: ExportedOnlyFixture.PublicContract {"))
        #expect(filteredOutput.contains("func publicCImportedTypeMember()"))
    }

    @Test func filteredOutputHasNoBlankLineArtifacts() async throws {
        let (filteredOutput, _) = try await buildOutput(exportedOnly: true)
        #expect(!filteredOutput.contains("\n\n\n"))
        #expect(!filteredOutput.contains("{\n}"))
    }
}
