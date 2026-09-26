import Foundation
import Testing
import MachOKit
@_spi(Internals) @testable import Demangling
@_spi(Internals) @testable import MachOSymbols
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@testable import MachOTestingSupport
import MachOFixtureSupport

/// `TypeDefinition.exportStatus` / `ProtocolDefinition.exportStatus` — the
/// export fact carried on the declaration model (evolution proposal
/// `exported-declaration-flag`), which the printer's `exportVerdict(...)`
/// and the `--exported-only` filter now read instead of computing.
///
/// The end-to-end consequences stay pinned where they were
/// (`ExportedOnlyInterfaceTests`, `ExportStatusAnnotationTests`); this suite
/// pins the fact itself.
@Suite(.serialized)
final class ExportStatusTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    private func preparedIndexer() async throws -> SwiftDeclarationIndexer<MachOFile> {
        let indexer = SwiftDeclarationIndexer(
            configuration: .init(showCImportedTypes: false),
            eventHandlers: [],
            in: machOFile
        )
        try await indexer.prepare()
        return indexer
    }

    /// The status must be exactly the trie's answer for the symbol sitting at
    /// the declaration's own descriptor — recomputed here from the store
    /// rather than read back through the model, so a change to the resolution
    /// order cannot make this test agree with itself.
    @Test func everyTypeStatusMatchesItsDescriptorSymbolTrieEntry() async throws {
        let unsafeMachOFile = machOFile
        let indexer = try await preparedIndexer()
        var exportedCount = 0
        var notExportedCount = 0

        for typeDefinition in indexer.allTypeDefinitions.values {
            let descriptorOffset = typeDefinition.typeContextDescriptorWrapper.typeContextDescriptor.offset
            let symbolsAtDescriptor = SymbolIndexStore.shared.symbols(for: descriptorOffset, in: unsafeMachOFile)
            let descriptorSymbol = symbolsAtDescriptor?.first { $0.name.isSwiftSymbol && $0.name.hasSuffix("Mn") }
            // Every type of this fixture carries a symbol at its own
            // descriptor — the measured norm on shipped binaries too, which is
            // why the remangling leg practically never runs.
            let descriptorSymbolName = try #require(descriptorSymbol?.name, "\(typeDefinition.typeName.name) has no descriptor symbol")
            let trieVerdict = SymbolIndexStore.shared.isExported(name: descriptorSymbolName, in: unsafeMachOFile)
            #expect(typeDefinition.exportStatus.isExported == trieVerdict, "\(typeDefinition.typeName.name)")

            switch typeDefinition.exportStatus {
            case .exported: exportedCount += 1
            case .notExported: notExportedCount += 1
            case .imageHasNoExportInformation, .descriptorSymbolNameUnresolvable:
                Issue.record("\(typeDefinition.typeName.name) reached a no-verdict case on an image that has an export trie")
            }
        }

        // Guards against a vacuous pass: both verdicts must actually occur.
        #expect(exportedCount > 0)
        #expect(notExportedCount > 0)
    }

    @Test func everyProtocolStatusMatchesItsDescriptorSymbolTrieEntry() async throws {
        let unsafeMachOFile = machOFile
        let indexer = try await preparedIndexer()
        var exportedCount = 0
        var notExportedCount = 0

        for protocolDefinition in indexer.allProtocolDefinitions.values {
            let descriptorOffset = protocolDefinition.protocolDescriptor.offset
            let symbolsAtDescriptor = SymbolIndexStore.shared.symbols(for: descriptorOffset, in: unsafeMachOFile)
            let descriptorSymbol = symbolsAtDescriptor?.first { $0.name.isSwiftSymbol && $0.name.hasSuffix("Mp") }
            let descriptorSymbolName = try #require(descriptorSymbol?.name, "\(protocolDefinition.protocolName.name) has no descriptor symbol")
            let trieVerdict = SymbolIndexStore.shared.isExported(name: descriptorSymbolName, in: unsafeMachOFile)
            #expect(protocolDefinition.exportStatus.isExported == trieVerdict, "\(protocolDefinition.protocolName.name)")

            switch protocolDefinition.exportStatus {
            case .exported: exportedCount += 1
            case .notExported: notExportedCount += 1
            case .imageHasNoExportInformation, .descriptorSymbolNameUnresolvable:
                Issue.record("\(protocolDefinition.protocolName.name) reached a no-verdict case on an image that has an export trie")
            }
        }

        #expect(exportedCount > 0)
        #expect(notExportedCount > 0)
    }

    /// The same declarations `ExportedOnlyInterfaceTests` rules on, asserted
    /// at the model level: a `private` type / protocol (local descriptor
    /// symbol) versus an exported one declared in the same file.
    @Test func knownDeclarationsCarryTheExpectedStatus() async throws {
        let unsafeMachOFile = machOFile
        let indexer = try await preparedIndexer()

        func typeDefinition(withDescriptorSymbolNamed symbolName: String) throws -> TypeDefinition {
            try #require(
                indexer.allTypeDefinitions.values.first { typeDefinition in
                    let offset = typeDefinition.typeContextDescriptorWrapper.typeContextDescriptor.offset
                    return SymbolIndexStore.shared.symbols(for: offset, in: unsafeMachOFile)?.contains { $0.name == symbolName } == true
                },
                "expected a type definition whose descriptor carries \(symbolName)"
            )
        }

        let privateType = try typeDefinition(withDescriptorSymbolNamed: "_$s15SymbolTestsCore19PrivateDoppelganger33_1282F137F8790A6AF4B7E2738A640142LLVMn")
        #expect(privateType.exportStatus == .notExported)
        #expect(privateType.exportStatus.isDefinitelyNotExported)

        let exportedNestedType = try typeDefinition(withDescriptorSymbolNamed: "_$s15SymbolTestsCore8GenericsO22GenericRequirementTestVAASYRzrlE28RawRepresentableNestedStructVMn")
        #expect(exportedNestedType.exportStatus == .exported)
        #expect(!exportedNestedType.exportStatus.isDefinitelyNotExported)

        let privateProtocolDescriptorName = "_$s15SymbolTestsCore27PrivateDoppelgangerProtocol33_1282F137F8790A6AF4B7E2738A640142LLMp"
        let privateProtocol = try #require(
            indexer.allProtocolDefinitions.values.first { protocolDefinition in
                SymbolIndexStore.shared.symbols(for: protocolDefinition.protocolDescriptor.offset, in: unsafeMachOFile)?
                    .contains { $0.name == privateProtocolDescriptorName } == true
            },
            "expected a protocol definition whose descriptor carries \(privateProtocolDescriptorName)"
        )
        #expect(privateProtocol.exportStatus == .notExported)
    }

    /// Why the descriptor-symbol leg is not optional:
    /// `Generics.GenericRequirementTest.RawRepresentableNestedStruct` is
    /// `public` and exported, but it is declared inside a CONSTRAINED
    /// extension, so remangling its model name node yields a spelling the
    /// compiler never emitted. The remangling leg must therefore refuse it
    /// (`nil`) instead of producing a name that misses the trie — a `false`
    /// there would drop an exported type.
    @Test func remanglingRefusesAConstrainedExtensionContext() async throws {
        let unsafeMachOFile = machOFile
        let indexer = try await preparedIndexer()
        let descriptorSymbolName = "_$s15SymbolTestsCore8GenericsO22GenericRequirementTestVAASYRzrlE28RawRepresentableNestedStructVMn"
        let nestedType = try #require(
            indexer.allTypeDefinitions.values.first { typeDefinition in
                let offset = typeDefinition.typeContextDescriptorWrapper.typeContextDescriptor.offset
                return SymbolIndexStore.shared.symbols(for: offset, in: unsafeMachOFile)?.contains { $0.name == descriptorSymbolName } == true
            }
        )

        #expect(ExportStatus.descriptorSymbolName(for: nestedType.typeName.node, descriptorKind: .nominalTypeDescriptor) == nil)
        // …and the descriptor-symbol leg still gets it right.
        #expect(nestedType.exportStatus == .exported)
    }
}

/// The projections, which every consumer rule is written against.
@Suite
struct ExportStatusProjectionTests {
    @Test func isExportedProjectsBothNoVerdictCasesToNil() {
        #expect(ExportStatus.exported.isExported == true)
        #expect(ExportStatus.notExported.isExported == false)
        #expect(ExportStatus.imageHasNoExportInformation.isExported == nil)
        #expect(ExportStatus.descriptorSymbolNameUnresolvable.isExported == nil)
    }

    /// The rule proposals 0008 / 0016 are built on: act only on a definitive
    /// negative, never on the absence of a verdict.
    @Test func onlyNotExportedIsDefinitelyNotExported() {
        #expect(ExportStatus.notExported.isDefinitelyNotExported)
        #expect(!ExportStatus.exported.isDefinitelyNotExported)
        #expect(!ExportStatus.imageHasNoExportInformation.isDefinitelyNotExported)
        #expect(!ExportStatus.descriptorSymbolNameUnresolvable.isDefinitelyNotExported)
    }
}
