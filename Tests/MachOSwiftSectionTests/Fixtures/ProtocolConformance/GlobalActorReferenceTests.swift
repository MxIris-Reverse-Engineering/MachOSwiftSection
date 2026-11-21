import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `GlobalActorReference`.
///
/// `GlobalActorReference` is the trailing object of
/// `TargetProtocolConformanceDescriptor` carrying the actor type that
/// isolates a conformance (e.g. `extension X: @MainActor P`). Present
/// iff `ProtocolConformanceFlags.hasGlobalActorIsolation` is set.
///
/// Picker: the first conformance from the fixture with the
/// `hasGlobalActorIsolation` bit, sourced from
/// `Actors.GlobalActorIsolatedConformanceTest: @MainActor ...`. The
/// `typeName(in:)` overload group (MachO + InProcess + ReadingContext)
/// collapses to a single MethodKey under PublicMemberScanner's name-based
/// deduplication; the Suite exercises both reader paths.
@Suite
@FixtureSuite
final class GlobalActorReferenceTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    private func loadFirstReferences() throws -> (file: GlobalActorReference, image: GlobalActorReference) {
        let fileConformance = try BaselineFixturePicker.protocolConformance_globalActorFirst(in: machOFile)
        let imageConformance = try BaselineFixturePicker.protocolConformance_globalActorFirst(in: machOImage)
        let file = try required(fileConformance.globalActorReference)
        let image = try required(imageConformance.globalActorReference)
        return (file: file, image: image)
    }

    @Test func offset() async throws {
        let (file, image) = try loadFirstReferences()
        let result = try acrossAllReaders(file, image) { $0.offset }
        #expect(result == GlobalActorReferenceBaseline.firstReference.offset)
    }

    @Test func layout() async throws {
        let (file, _) = try loadFirstReferences()
        // The layout carries the relative `type` MangledName pointer plus
        // the relative `conformance` raw offset. Exercise their
        // accessibility — the `type` resolution is exercised by `typeName`.
        _ = file.layout.type
        _ = file.layout.conformance
    }

    /// `typeName(in:)` is exposed in three overloads (MachO + in-process
    /// + ReadingContext) that all collapse to a single `MethodKey` under
    /// PublicMemberScanner's name-based key. Exercise the ReadingContext
    /// overload over both readers here.
    @Test func typeName() async throws {
        let (file, image) = try loadFirstReferences()
        let result = try acrossAllContexts(file, image) { reference, context in try reference.typeName(in: context).symbolString }
        #expect(result == GlobalActorReferenceBaseline.firstReference.typeNameSymbolString)
    }
}
