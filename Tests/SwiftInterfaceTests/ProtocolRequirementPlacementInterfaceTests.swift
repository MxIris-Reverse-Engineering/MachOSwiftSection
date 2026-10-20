import Foundation
import Testing
import MachOKit
import MachOSwiftSection
import SwiftDeclarationRendering
@_spi(Support) @testable import SwiftIndexing
@_spi(Support) @testable import SwiftPrinting
@_spi(Support) @testable import SwiftInterface
@testable import MachOTestingSupport

/// How the interface prints a protocol's requirement signature (evolution
/// proposal `protocol-requirement-placement`): every requirement in the
/// protocol's `where` clause, or each on the associated type it is about. The
/// binary cannot say where the source wrote a requirement, so the one thing
/// both placements must guarantee is that they state the same requirements —
/// which `printedProtocolsCompileBackToTheSameRequirementSignatures` checks
/// the only way that does not trust the printer: compiling what it printed.
@Suite(.serialized)
struct ProtocolRequirementPlacementInterfaceTests {
    private func printedInterface(of machOFile: MachOFile, configuration printConfiguration: SwiftDeclarationPrintConfiguration = .init()) async throws -> String {
        let builder = try SwiftInterfaceBuilder(configuration: .init(printConfiguration: printConfiguration), eventHandlers: [], in: machOFile)
        try await builder.prepare()
        return try await builder.printRoot().string
    }

    private static func configuration(placement: ProtocolRequirementPlacement) -> SwiftDeclarationPrintConfiguration {
        var configuration = SwiftDeclarationPrintConfiguration()
        configuration.protocolRequirementPlacement = placement
        return configuration
    }

    /// A top-level protocol's lines, header to closing brace.
    private static func protocolBlock(named name: String, in interface: String) -> String? {
        let lines = interface.components(separatedBy: "\n")
        guard let headerIndex = lines.firstIndex(where: { $0.hasPrefix("protocol \(name):") || $0.hasPrefix("protocol \(name) ") }) else { return nil }
        if lines[headerIndex].hasSuffix("{}") {
            return lines[headerIndex]
        }
        guard let closingIndex = lines[headerIndex...].firstIndex(of: "}") else { return nil }
        return lines[headerIndex ... closingIndex].joined(separator: "\n")
    }

    /// Each protocol's requirement signature as its descriptor records it,
    /// printed by the demangler (`A.Second == [A.First]`) through the generic
    /// requirement dump, never through the protocol printer under test.
    private static func requirementSignatures(in machOFile: MachOFile) async throws -> [String: [String]] {
        var requirementSignatures: [String: [String]] = [:]
        for protocolDescriptor in try machOFile.swift.protocolDescriptors {
            let protocolModel = try MachOSwiftSection.`Protocol`(descriptor: protocolDescriptor, in: machOFile.context)
            var requirements: [String] = []
            for requirement in protocolModel.requirementInSignatures {
                let requirementText = try await requirement.descriptor.dump(using: .default, in: machOFile.context).string
                requirements.append("\(requirement.descriptor.flags.kind) \(requirementText)")
            }
            requirementSignatures[protocolModel.name] = requirements
        }
        return requirementSignatures
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

    // MARK: - Placement

    struct PlacementCase: Sendable, CustomTestStringConvertible {
        let protocolName: String
        let blockWithRequirementsOnAssociatedTypes: String

        var testDescription: String { protocolName }
    }

    /// The blocks follow the compiler's `-emit-module-interface` for the same
    /// source, except `RecursiveRequirements`, where the compiler prints
    /// `associatedtype Leaf : Swift.Hashable` — a requirement on `Self.Leaf`
    /// that the protocol does not have.
    static let placementCases: [PlacementCase] = [
        PlacementCase(
            protocolName: "CompositeRequirements",
            blockWithRequirementsOnAssociatedTypes: """
            protocol CompositeRequirements {
                associatedtype First
                associatedtype Second where Self.Second == [Self.First]
                associatedtype Third where Self.Third == (Self.First, [Self.First])
                associatedtype Fourth where Self.Fourth == Self.First?
                associatedtype Fifth: ProtocolRequirementPlacementFixture.GenericBase<Self.First>
                associatedtype Sixth where Self.Sixth == [Self]
                associatedtype Seventh: ProtocolRequirementPlacementFixture.Marker, Swift.Sequence
                associatedtype Eighth where Self.Eighth == [Self.Seventh.Element]
            }
            """
        ),
        PlacementCase(
            protocolName: "DirectRequirements",
            blockWithRequirementsOnAssociatedTypes: """
            protocol DirectRequirements {
                associatedtype Conforming: ProtocolRequirementPlacementFixture.Marker, Swift.Hashable
                associatedtype Subclass: ProtocolRequirementPlacementFixture.BaseClass
                associatedtype ClassBound: AnyObject
                associatedtype ClassAndProtocol: ProtocolRequirementPlacementFixture.BaseClass, ProtocolRequirementPlacementFixture.Marker
                associatedtype Nested: Swift.Sequence where Self.Nested.Element: ProtocolRequirementPlacementFixture.Marker
                associatedtype Concrete where Self.Concrete == Swift.Int
            }
            """
        ),
        PlacementCase(
            protocolName: "SameTypeRequirements",
            blockWithRequirementsOnAssociatedTypes: """
            protocol SameTypeRequirements {
                associatedtype First where Self.First == Self.Second.Target
                associatedtype Second: ProtocolRequirementPlacementFixture.Pointing
                associatedtype Third: ProtocolRequirementPlacementFixture.Pointing where Self == Self.Third.Target
            }
            """
        ),
        PlacementCase(
            protocolName: "RecursiveRequirements",
            blockWithRequirementsOnAssociatedTypes: """
            protocol RecursiveRequirements {
                associatedtype Child: ProtocolRequirementPlacementFixture.RecursiveRequirements where Self.Child.Leaf: Swift.Hashable
                associatedtype Leaf
            }
            """
        ),
        PlacementCase(
            protocolName: "RefinedRequirements",
            blockWithRequirementsOnAssociatedTypes: """
            protocol RefinedRequirements: Swift.Sequence where Self.Element: ProtocolRequirementPlacementFixture.Marker {
                associatedtype Storage: Swift.Collection where Self.Element == Self.Storage.Element
            }
            """
        ),
        PlacementCase(
            protocolName: "InheritedOnlyRequirements",
            blockWithRequirementsOnAssociatedTypes: """
            protocol InheritedOnlyRequirements: Swift.Sequence where Self.Element: Swift.Hashable {}
            """
        ),
        PlacementCase(
            protocolName: "ClassBoundRequirements",
            blockWithRequirementsOnAssociatedTypes: """
            protocol ClassBoundRequirements: AnyObject {
                associatedtype Item: AnyObject
            }
            """
        ),
        PlacementCase(
            protocolName: "MenuRequirements",
            blockWithRequirementsOnAssociatedTypes: """
            protocol MenuRequirements: Swift.Identifiable {
                associatedtype MenuItem: ProtocolRequirementPlacementFixture.Marker
            }
            """
        ),
    ]

    @Test(arguments: placementCases)
    func requirementsPrintOnTheAssociatedTypesTheyAreAbout(_ placementCase: PlacementCase) async throws {
        let interface = try await printedInterface(of: ProtocolRequirementPlacementFixture.machOFile(), configuration: Self.configuration(placement: .associatedTypes))
        let block = try #require(Self.protocolBlock(named: placementCase.protocolName, in: interface), "\(interface)")
        #expect(block == placementCase.blockWithRequirementsOnAssociatedTypes)
    }

    /// The default keeps every requirement in the protocol's header, so no
    /// `associatedtype` line carries one.
    @Test(arguments: ProtocolRequirementPlacementFixture.protocolNames)
    func defaultPlacementLeavesEveryAssociatedTypeBare(protocolName: String) async throws {
        let interface = try await printedInterface(of: ProtocolRequirementPlacementFixture.machOFile())
        let block = try #require(Self.protocolBlock(named: protocolName, in: interface), "\(interface)")
        for line in block.components(separatedBy: "\n").dropFirst() {
            #expect(!line.contains(":") && !line.contains(" where "), "\(protocolName): \(line)")
        }
    }

    /// The guarantee both placements make: what they print states the
    /// protocol's requirement signature exactly. Each printed form of the
    /// fixture's protocols is compiled again, as the same module and against
    /// the same supporting declarations, and every protocol must come back
    /// with the requirement signature it started from — the canonical
    /// signature being all the binary ever knew of the source.
    @Test(arguments: ProtocolRequirementPlacement.allCases)
    func printedProtocolsCompileBackToTheSameRequirementSignatures(placement: ProtocolRequirementPlacement) async throws {
        let fixture = try ProtocolRequirementPlacementFixture.machOFile()
        let interface = try await printedInterface(of: fixture, configuration: Self.configuration(placement: placement))
        let printedProtocols = try ProtocolRequirementPlacementFixture.protocolNames.map { protocolName in
            try #require(Self.protocolBlock(named: protocolName, in: interface), "\(protocolName) missing from:\n\(interface)")
        }
        let printedSource = printedProtocols.joined(separator: "\n\n")
        let recompiledFixture = try ProtocolRequirementPlacementFixture.machOFile(compiling: printedSource)

        let originalRequirementSignatures = try await Self.requirementSignatures(in: fixture)
        let recompiledRequirementSignatures = try await Self.requirementSignatures(in: recompiledFixture)
        for protocolName in ProtocolRequirementPlacementFixture.protocolNames {
            let originalRequirementSignature = try #require(originalRequirementSignatures[protocolName])
            #expect(recompiledRequirementSignatures[protocolName] == originalRequirementSignature, "\(protocolName), printed as:\n\(printedSource)")
        }
    }

    /// The diff and evolution interfaces print a protocol's `associatedtype`
    /// lines without requirements, so their header keeps every requirement
    /// whatever the placement says — the same header the default prints.
    @Test(arguments: ProtocolRequirementPlacementFixture.protocolNames)
    func diffHeaderKeepsEveryRequirement(protocolName: String) async throws {
        let fixture = try ProtocolRequirementPlacementFixture.machOFile()
        let defaultInterface = try await printedInterface(of: fixture)
        let defaultHeader = try #require(Self.protocolBlock(named: protocolName, in: defaultInterface)?.components(separatedBy: "\n").first, "\(defaultInterface)")

        let builder = try SwiftInterfaceBuilder(configuration: .init(printConfiguration: Self.configuration(placement: .associatedTypes)), eventHandlers: [], in: fixture)
        try await builder.prepare()
        let qualifiedName = "\(ProtocolRequirementPlacementFixture.moduleName).\(protocolName)"
        let protocolDefinition = try #require(builder.indexer.allProtocolDefinitions.values.first { $0.protocolName.name == qualifiedName })
        let diffHeader = try await builder.printer.printProtocolHeader(protocolDefinition, level: 1).string
        #expect(defaultHeader.hasPrefix(diffHeader + " {"), "\(diffHeader)\n\(defaultHeader)")
    }
}
