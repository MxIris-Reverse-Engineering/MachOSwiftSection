import Foundation
import Testing
import MachOKit
import MachOSwiftSection
import SwiftDiffing
@testable import MachOTestingSupport
import MachOFixtureSupport
@testable import SwiftInterface

/// A stored property of a constrained existential type (`any Boxed<Int>`)
/// reaches the field record as a symbolic reference to an extended existential
/// type shape — `any Boxed<τ_0_0>` — plus the arguments that instantiate it,
/// `[Swift.Int]`. The interface printed the arguments alone, so the property
/// read `var boxed: Swift.Int`: a real, wrong type. The ABI snapshot recorded
/// the symbolic form, which printed every such field of `Swift.Int` the same,
/// whatever its protocol (evolution proposal `existential-any`).
@Suite
final class ConstrainedExistentialFieldTests: MachOFileTests, SnapshotInterfaceTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    private static let holderName = "SymbolTestsCore.GenericFieldLayout.ConstrainedExistentialFieldHolder"

    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    @Test func interfacePrintsTheConstrainedExistentialOfAStoredProperty() async throws {
        let interface = try await collectInterfaceString(in: machOFile)
        #expect(interface.contains("var boxed: any SymbolTestsCore.GenericFieldLayout.Boxed<Swift.Int>\n"))
        #expect(interface.contains("var optionalBoxed: (any SymbolTestsCore.GenericFieldLayout.Boxed<Swift.String>)?\n"))
    }

    @Test func abiSnapshotRecordsTheProtocolOfAConstrainedExistentialField() async throws {
        let builder = SwiftDiffableInterfaceBuilder(in: machOFile)
        try await builder.prepare()
        let snapshot = builder.snapshot()
        let holder = try #require(snapshot.types.first { $0.name == Self.holderName })
        let boxed = try #require(holder.members.first { $0.kind == .field && $0.signature.hasPrefix("boxed: ") })
        let optionalBoxed = try #require(holder.members.first { $0.kind == .field && $0.signature.hasPrefix("optionalBoxed: ") })
        #expect(boxed.signature.contains("SymbolTestsCore.GenericFieldLayout.Boxed<"), "\(boxed.signature)")
        #expect(boxed.signature.contains("Swift.Int"), "\(boxed.signature)")
        #expect(optionalBoxed.signature.contains("SymbolTestsCore.GenericFieldLayout.Boxed<"), "\(optionalBoxed.signature)")
        #expect(optionalBoxed.signature.contains("Swift.String"), "\(optionalBoxed.signature)")
    }
}
