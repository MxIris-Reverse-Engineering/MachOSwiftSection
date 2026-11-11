import Foundation
import Testing
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDump
@testable import MachOTestingSupport

/// `dump` with `DemangleOptions.useExistentialAny` (evolution proposal
/// `existential-any`): the field types swift-demangling prints spell
/// existentials with the `any` keyword, by the compiler's rules. The dump
/// turns the option on by default; these cases pin the field lines with and
/// without it.
@Suite
struct ExistentialAnyDumpTests {
    private func shapesDump(options: DemangleOptions) async throws -> String {
        let machOFile = try ExistentialAnyFixture.machOFile()
        for typeContextDescriptor in try machOFile.swift.typeContextDescriptors {
            guard case .struct(let structDescriptor) = typeContextDescriptor, try structDescriptor.name(in: machOFile.context) == "Shapes" else { continue }
            return try await Struct(descriptor: structDescriptor, in: machOFile.context).dump(using: .demangleOptions(options), in: machOFile).string
        }
        Issue.record("struct Shapes not found")
        return ""
    }

    @Test(arguments: [
        ("var single: ExistentialAnyFixture.Marker\n", "var single: any ExistentialAnyFixture.Marker\n"),
        ("var classBound: ExistentialAnyFixture.Marker & Swift.AnyObject\n", "var classBound: any ExistentialAnyFixture.Marker & Swift.AnyObject\n"),
        ("var anything: Any\n", "var anything: Any\n"),
        ("var anyObject: Swift.AnyObject\n", "var anyObject: Swift.AnyObject\n"),
        ("var collection: Swift.Collection\n", "var collection: any Swift.Collection\n"),
        ("var optional: ExistentialAnyFixture.Marker?\n", "var optional: (any ExistentialAnyFixture.Marker)?\n"),
        ("var optionalAnything: Any?\n", "var optionalAnything: Any?\n"),
        ("var existentialMetatype: ExistentialAnyFixture.Marker.Type\n", "var existentialMetatype: any ExistentialAnyFixture.Marker.Type\n"),
        ("var compositionMetatype: ExistentialAnyFixture.Marker & ExistentialAnyFixture.SecondMarker.Type\n", "var compositionMetatype: any (ExistentialAnyFixture.Marker & ExistentialAnyFixture.SecondMarker).Type\n"),
        ("var anythingMetatype: Any.Type\n", "var anythingMetatype: any Any.Type\n"),
        ("var optionalExistentialMetatype: ExistentialAnyFixture.Marker.Type?\n", "var optionalExistentialMetatype: (any ExistentialAnyFixture.Marker.Type)?\n"),
        ("var protocolMetatype: ExistentialAnyFixture.Marker.Protocol\n", "var protocolMetatype: (any ExistentialAnyFixture.Marker).Type\n"),
        ("var existentialArray: [ExistentialAnyFixture.Marker]\n", "var existentialArray: [any ExistentialAnyFixture.Marker]\n"),
        ("var existentialFunction: (ExistentialAnyFixture.Marker) -> ExistentialAnyFixture.SecondMarker\n", "var existentialFunction: (any ExistentialAnyFixture.Marker) -> any ExistentialAnyFixture.SecondMarker\n"),
    ])
    func fieldTypesFollowTheOption(bareSpelling: String, spellingWithKeyword: String) async throws {
        let bareDump = try await shapesDump(options: .interface)
        #expect(bareDump.contains(bareSpelling), "\(bareDump)")
        let dump = try await shapesDump(options: DemangleOptions.interface.union(.useExistentialAny))
        #expect(dump.contains(spellingWithKeyword), "\(dump)")
    }

    /// A constrained existential carries its keyword with or without the
    /// option, and names its protocol: its field record holds a shape plus the
    /// arguments, which used to print as `symbolic existential type … <…>`.
    @Test func constrainedExistentialFieldsNameTheirProtocol() async throws {
        for options in [DemangleOptions.interface, DemangleOptions.interface.union(.useExistentialAny)] {
            let fieldLines = try await shapesDump(options: options).split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            let constrained = try #require(fieldLines.first { $0.hasPrefix("var constrained: ") })
            let constrainedMetatype = try #require(fieldLines.first { $0.hasPrefix("var constrainedMetatype: ") })
            #expect(constrained.hasPrefix("var constrained: any ExistentialAnyFixture.Boxed<") && constrained.contains("Swift.Int"), "\(constrained)")
            #expect(constrainedMetatype.hasPrefix("var constrainedMetatype: any ExistentialAnyFixture.Boxed<") && constrainedMetatype.hasSuffix(">.Type"), "\(constrainedMetatype)")
        }
    }
}
