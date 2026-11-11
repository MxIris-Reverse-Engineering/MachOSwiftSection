import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDump
@testable import MachOTestingSupport

/// `dump` names the macro that generated an `@Observable` class's members on
/// its header line and keeps every member as the records have them
/// (evolution proposal `observable-macro-folding`).
@Suite
struct ObservableMacroDumpTests {
    private func classDumps(_ variant: ObservableMacroFixture.Variant, options: DemangleOptions = .interface) async throws -> [String: String] {
        let machOFile = try ObservableMacroFixture.machOFile(variant)
        var dumps: [String: String] = [:]
        for typeContextDescriptor in try machOFile.swift.typeContextDescriptors {
            guard case .class(let classDescriptor) = typeContextDescriptor else { continue }
            let name = try classDescriptor.name(in: machOFile.context)
            dumps[name] = try await Class(descriptor: classDescriptor, in: machOFile.context).dump(using: .demangleOptions(options), in: machOFile).string
        }
        return dumps
    }

    @Test(arguments: ObservableMacroFixture.Variant.allCases)
    func theHeaderNamesTheMacro(variant: ObservableMacroFixture.Variant) async throws {
        let dumps = try await classDumps(variant)
        for name in ObservableMacroFixture.observableClassNames {
            let dump = try #require(dumps[name], "no class \(name)")
            #expect(dump.hasPrefix("@Observation.Observable class ObservableMacroFixture."), "\(dump)")
        }
        for name in ObservableMacroFixture.lookalikeTypeNames where name != "Clamped" {
            let dump = try #require(dumps[name], "no class \(name)")
            #expect(!dump.contains("@Observation"), "\(dump)")
        }
        // Everything the macro generated stays.
        let finalModel = try #require(dumps["FinalModel"])
        for generated in ["_$observationRegistrar", "var _name: Swift.String"] {
            #expect(finalModel.contains(generated), "\(generated) not in:\n\(finalModel)")
        }
    }

    @Test func theAttributeFollowsTheDemangleOptions() async throws {
        let dumps = try await classDumps(.release, options: DemangleOptions.interface.union([.useModuleSelectors, .useExistentialAny]))
        let dump = try #require(dumps["FinalModel"])
        #expect(dump.hasPrefix("@Observation::Observable class ObservableMacroFixture::FinalModel"), "\(dump)")
    }
}
