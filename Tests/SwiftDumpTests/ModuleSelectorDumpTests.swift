import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDump
@testable import MachOTestingSupport

/// `dump` with `DemangleOptions.useModuleSelectors` (evolution proposal
/// `module-selectors`): the names swift-demangling prints follow the option,
/// and so do the suppressed conformances the dumper spells itself.
@Suite
struct ModuleSelectorDumpTests {
    private func structDump(named name: String, options: DemangleOptions) async throws -> String {
        let machOFile = try ModuleSelectorFixture.machOFile()
        for typeContextDescriptor in try machOFile.swift.typeContextDescriptors {
            guard case .struct(let structDescriptor) = typeContextDescriptor, try structDescriptor.name(in: machOFile.context) == name else { continue }
            return try await Struct(descriptor: structDescriptor, in: machOFile.context).dump(using: .demangleOptions(options), in: machOFile).string
        }
        Issue.record("struct \(name) not found")
        return ""
    }

    @Test(arguments: [
        ("ModuleSelectorFixture.Outer.Inner", "ModuleSelectorFixture::Outer.ModuleSelectorFixture::Inner"),
        ("Swift.Duration.LocalFormat", "Swift::Duration.ModuleSelectorFixture::LocalFormat"),
        ("ModuleSelectorFixture.Marker & Swift.AnyObject", "ModuleSelectorFixture::Marker & Swift::AnyObject"),
    ])
    func fieldTypesFollowTheOption(spellingWithoutSelectors: String, spellingWithSelectors: String) async throws {
        let dumpWithoutSelectors = try await structDump(named: "Shapes", options: .interface)
        #expect(dumpWithoutSelectors.contains(spellingWithoutSelectors), "\(dumpWithoutSelectors)")
        let dumpWithSelectors = try await structDump(named: "Shapes", options: DemangleOptions.interface.union(.useModuleSelectors))
        #expect(dumpWithSelectors.contains(spellingWithSelectors), "\(dumpWithSelectors)")
    }

    @Test func suppressedConformanceFollowsTheOption() async throws {
        let dumpWithoutSelectors = try await structDump(named: "Unique", options: .interface)
        #expect(dumpWithoutSelectors.contains("struct ModuleSelectorFixture.Unique: ~Swift.Copyable"), "\(dumpWithoutSelectors)")
        let dumpWithSelectors = try await structDump(named: "Unique", options: DemangleOptions.interface.union(.useModuleSelectors))
        #expect(dumpWithSelectors.contains("struct ModuleSelectorFixture::Unique: ~Swift::Copyable"), "\(dumpWithSelectors)")
    }

    /// The sweep over every type, protocol and conformance the fixture
    /// dumps: no name left qualified the dotted way by a module the dump
    /// spells with a selector somewhere.
    @Test func noNameKeepsItsDottedQualification() async throws {
        let machOFile = try ModuleSelectorFixture.machOFile()
        let options = DemangleOptions.interface.union(.useModuleSelectors)
        var dumps: [String] = []
        for typeContextDescriptor in try machOFile.swift.typeContextDescriptors {
            switch typeContextDescriptor {
            case .struct(let structDescriptor):
                try await dumps.append(Struct(descriptor: structDescriptor, in: machOFile.context).dump(using: .demangleOptions(options), in: machOFile).string)
            case .enum(let enumDescriptor):
                try await dumps.append(Enum(descriptor: enumDescriptor, in: machOFile.context).dump(using: .demangleOptions(options), in: machOFile).string)
            case .class(let classDescriptor):
                try await dumps.append(Class(descriptor: classDescriptor, in: machOFile.context).dump(using: .demangleOptions(options), in: machOFile).string)
            }
        }
        for protocolDescriptor in try machOFile.swift.protocolDescriptors {
            try await dumps.append(MachOSwiftSection.`Protocol`(descriptor: protocolDescriptor, in: machOFile.context).dump(using: .demangleOptions(options), in: machOFile).string)
        }
        for protocolConformanceDescriptor in try machOFile.swift.protocolConformanceDescriptors {
            try await dumps.append(ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machOFile.context).dump(using: .demangleOptions(options), in: machOFile).string)
        }
        let dump = dumps.joined(separator: "\n")
        #expect(dump.contains("Swift::") && dump.contains("\(ModuleSelectorFixture.moduleName)::"), "\(dump)")
        for dottedQualification in ModuleSelectorFixture.dottedQualifications(in: dump) {
            Issue.record("dotted qualification `\(dottedQualification.qualifiedName)` left in: \(dottedQualification.line)")
        }
    }
}
