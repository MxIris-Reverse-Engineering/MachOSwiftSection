import Foundation
import Testing
import MachOKit
import Demangling
import Semantic
@_spi(Support) @testable import SwiftDeclaration
@_spi(Support) @testable import SwiftIndexing
@_spi(Support) @testable import SwiftPrinting
@_spi(Support) @testable import SwiftInterface
@testable import MachOTestingSupport
import MachOFixtureSupport

/// The protocol a conformance extension names is a type reference like any
/// other, so its name must carry the semantic type the rest of the interface
/// gives type references — RuntimeViewer highlights a name and links it to its
/// declaration by that type. The header printed it through the demangler's
/// generic `printSemantic` (inherited from SwiftDump's `dumpProtocolName`)
/// rather than this printer's own type printer, and that path lost both
/// halves for a `private` / `fileprivate` name: the conformance below rendered
/// `PrivateDoppelgangerProtocol` as `.standard` text with no span identity —
/// no highlighting, no link — while the same protocol named in a member
/// signature was a linked protocol type name.
@Suite(.serialized)
final class ConformanceProtocolNameSemanticsTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    @Test func privateProtocolInConformanceClauseIsAProtocolTypeReference() async throws {
        let unsafeMachOFile = machOFile
        let builder = try SwiftInterfaceBuilder(configuration: .init(), eventHandlers: [], in: unsafeMachOFile)
        try await builder.prepare()

        let conformanceHeader = "extension SymbolTestsCore.AlphaProtocolWitness: SymbolTestsCore.PrivateDoppelgangerProtocol {}"
        var renderedConformance: SemanticString?
        for extensionDefinition in builder.indexer.conformanceExtensionDefinitions.values.joined() where extensionDefinition.extensionName.name.hasSuffix("AlphaProtocolWitness") {
            let rendered = try await builder.printer.printExtensionDefinition(extensionDefinition)
            if rendered.string.trimmingCharacters(in: .whitespacesAndNewlines) == conformanceHeader {
                renderedConformance = rendered
            }
        }
        let rendered = try #require(renderedConformance, "the premise: the fixture renders \(conformanceHeader)")

        let protocolNameComponents = rendered.components.filter { $0.string == "PrivateDoppelgangerProtocol" }
        try #require(protocolNameComponents.count == 1, "the premise: the protocol's name is written once")
        let protocolNameComponent = protocolNameComponents[0]
        #expect(protocolNameComponent.type == .type(.protocol, .name))

        // The link half: the name's span identity is the key a jump looks the
        // protocol up by, the mangled name of the indexed declaration.
        let identifier = try #require(protocolNameComponent.identifier)
        let declarationMangledNames = try builder.indexer.allProtocolDefinitions.keys
            .filter { $0.name.hasSuffix("PrivateDoppelgangerProtocol") }
            .map { try mangleAsString($0.node) }
        #expect(declarationMangledNames.contains(identifier), "\(identifier) is none of \(declarationMangledNames)")
    }
}
