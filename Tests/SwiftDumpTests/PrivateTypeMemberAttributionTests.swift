import Foundation
import Testing
import MachOKit
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Issue #115: two top-level `private struct PrivateDoppelganger` declarations
/// (one per fixture file) share their interface-printed name — the private
/// discriminator is exactly what `DemangleOptions.interface` strips — so the
/// dump path's name-keyed member lookup used to flatten both types' symbol
/// buckets into every declaration: each struct printed its own `init` and
/// method *plus* the other file's. The fixture pair keeps the two member sets
/// disjoint (`alpha*` vs `beta*`), so a merge is directly observable.
@Suite
final class PrivateTypeMemberAttributionTests: MachOFileTests, @unchecked Sendable {
    override class var fileName: MachOFileName { .SymbolTestsCore }

    @Test func sameNamedPrivateTypesKeepTheirOwnMembers() async throws {
        var dumpsByFieldMarker: [String: String] = [:]
        for typeContextDescriptor in try machOFile.swift.typeContextDescriptors {
            guard
                case .struct(let structDescriptor) = typeContextDescriptor,
                try structDescriptor.name(in: machOFile) == "PrivateDoppelganger"
            else { continue }
            let structType = try Struct(descriptor: structDescriptor, in: machOFile)
            let output = try await structType.dump(using: .demangleOptions(.test), in: machOFile).string
            if output.contains("alphaStorage") {
                dumpsByFieldMarker["alpha"] = output
            } else if output.contains("betaStorage") {
                dumpsByFieldMarker["beta"] = output
            }
        }

        let alphaDump = try #require(dumpsByFieldMarker["alpha"], "fixture carries no alpha-file PrivateDoppelganger struct")
        let betaDump = try #require(dumpsByFieldMarker["beta"], "fixture carries no beta-file PrivateDoppelganger struct")

        // Each declaration must list its own members...
        #expect(alphaDump.contains("alphaSeed"), "alpha declaration lost its own initializer:\n\(alphaDump)")
        #expect(alphaDump.contains("alphaOnlyMethod"), "alpha declaration lost its own method:\n\(alphaDump)")
        #expect(betaDump.contains("betaSeed"), "beta declaration lost its own initializer:\n\(betaDump)")
        #expect(betaDump.contains("betaOnlyMethod"), "beta declaration lost its own method:\n\(betaDump)")

        // ...and none of the same-named sibling's (the issue-#115 merge).
        #expect(!alphaDump.contains("betaSeed"), "alpha declaration lists the beta initializer:\n\(alphaDump)")
        #expect(!alphaDump.contains("betaOnlyMethod"), "alpha declaration lists the beta method:\n\(alphaDump)")
        #expect(!betaDump.contains("alphaSeed"), "beta declaration lists the alpha initializer:\n\(betaDump)")
        #expect(!betaDump.contains("alphaOnlyMethod"), "beta declaration lists the alpha method:\n\(betaDump)")
    }
}
