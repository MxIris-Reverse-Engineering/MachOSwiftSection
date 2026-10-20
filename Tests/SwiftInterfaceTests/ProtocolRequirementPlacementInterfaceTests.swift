import Foundation
import Testing
import MachOKit
@_spi(Support) @testable import SwiftPrinting
@_spi(Support) @testable import SwiftInterface
@testable import MachOTestingSupport

/// How the interface prints a protocol's requirement signature (evolution
/// proposal `protocol-requirement-placement`).
@Suite(.serialized)
struct ProtocolRequirementPlacementInterfaceTests {
    private func printedInterface(of machOFile: MachOFile, configuration printConfiguration: SwiftDeclarationPrintConfiguration = .init()) async throws -> String {
        let builder = try SwiftInterfaceBuilder(configuration: .init(printConfiguration: printConfiguration), eventHandlers: [], in: machOFile)
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    // MARK: - Composite right-hand sides

    /// A same-type or superclass requirement whose right-hand side is a
    /// composite type prints that type. Reading only the associated type
    /// names out of it printed a different requirement:
    /// `Self.Second == [Self.First]` as `Self.Second == Self.First`.
    @Test(arguments: [
        "Self.Second == [Self.First]",
        "Self.Third == (Self.First, [Self.First])",
        "Self.Fourth == Self.First?",
        "Self.Fifth: ProtocolRequirementPlacementFixture.GenericBase<Self.First>",
        "Self.Sixth == [Self]",
        "Self.Eighth == [Self.Seventh.Element]",
    ])
    func compositeRightHandSidePrintsAsItself(requirement: String) async throws {
        let interface = try await printedInterface(of: ProtocolRequirementPlacementFixture.machOFile())
        #expect(interface.contains(requirement), "\(interface)")
    }
}
