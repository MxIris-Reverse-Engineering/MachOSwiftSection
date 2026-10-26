import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDump
@testable import MachOTestingSupport

/// A protocol's same-type or superclass requirement whose right-hand side is
/// a composite type prints that type (evolution proposal
/// `protocol-requirement-placement`). Reading only the associated type names
/// out of it printed a different requirement: `Self.Second == [Self.First]`
/// as `Self.Second == Self.First`, `Self.Sixth == [Self]` as
/// `Self.Sixth == [A]`.
@Suite
struct ProtocolRequirementRightHandSideDumpTests {
    private func protocolDump(named name: String) async throws -> String {
        let machOFile = try ProtocolRequirementPlacementFixture.machOFile()
        for protocolDescriptor in try machOFile.swift.protocolDescriptors {
            guard try protocolDescriptor.name(in: machOFile.context) == name else { continue }
            return try await MachOSwiftSection.`Protocol`(descriptor: protocolDescriptor, in: machOFile.context).dump(using: .demangleOptions(.interface), in: machOFile).string
        }
        Issue.record("protocol \(name) not found")
        return ""
    }

    @Test(arguments: [
        "Self.Second == [Self.First]",
        "Self.Third == (Self.First, [Self.First])",
        "Self.Fourth == Self.First?",
        "Self.Fifth: ProtocolRequirementPlacementFixture.GenericBase<Self.First>",
        "Self.Sixth == [Self]",
        "Self.Eighth == [Self.Seventh.Element]",
    ])
    func compositeRightHandSidePrintsAsItself(requirement: String) async throws {
        let dump = try await protocolDump(named: "CompositeRequirements")
        #expect(dump.contains(requirement), "\(dump)")
    }
}
