import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

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
final class GlobalActorReferenceTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "GlobalActorReference"
    static var registeredTestMethodNames: Set<String> {
        GlobalActorReferenceBaseline.registeredTestMethodNames
    }

    private func loadFirstReferences() throws -> (file: GlobalActorReference, image: GlobalActorReference) {
        let fileConformance = try BaselineFixturePicker.protocolConformance_globalActorFirst(in: machOFile)
        let imageConformance = try BaselineFixturePicker.protocolConformance_globalActorFirst(in: machOImage)
        let file = try required(fileConformance.globalActorReference)
        let image = try required(imageConformance.globalActorReference)
        return (file: file, image: image)
    }

    @Test func offset() async throws {
        let (file, image) = try loadFirstReferences()
        let result = try acrossAllReaders(
            file: { file.offset },
            image: { image.offset }
        )
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
    /// PublicMemberScanner's name-based key. Exercise the MachO and
    /// ReadingContext overloads here.
    @Test func typeName() async throws {
        let (file, image) = try loadFirstReferences()
        let result = try acrossAllReaders(
            file: { try file.typeName(in: machOFile).symbolString },
            image: { try image.typeName(in: machOImage).symbolString }
        )
        #expect(result == GlobalActorReferenceBaseline.firstReference.typeNameSymbolString)

        // ReadingContext overload also exercised.
        let imageContextResult = try image.typeName(in: imageContext).symbolString
        #expect(imageContextResult == GlobalActorReferenceBaseline.firstReference.typeNameSymbolString)
    }
}
