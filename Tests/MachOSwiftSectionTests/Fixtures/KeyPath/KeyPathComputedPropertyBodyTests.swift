import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `KeyPathComputedPropertyBody`.
///
/// The carrier is `CodableTests.CodableClassTest.identifier` — a settable
/// property of a resilient class, so all three words (identifier, getter,
/// setter) are present. Every offset the body reports is pure
/// relative-pointer arithmetic off the body's own location, so both readers
/// must agree, and the values are pinned as literals.
@Suite
final class KeyPathComputedPropertyBodyTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "KeyPathComputedPropertyBody"
    static var registeredTestMethodNames: Set<String> {
        KeyPathComputedPropertyBodyBaseline.registeredTestMethodNames
    }

    private var expected: KeyPathComputedPropertyBodyBaseline.Entry {
        KeyPathComputedPropertyBodyBaseline.codableClassIdentifier
    }

    private func loadBodies() throws -> (file: KeyPathComputedPropertyBody, image: KeyPathComputedPropertyBody) {
        let fileDescriptors = try KeyPathFixtureDescriptors(in: machOFile)
        let imageDescriptors = try KeyPathFixtureDescriptors(in: machOImage)
        return (
            file: try required(fileDescriptors.computedSettable.computedPropertyBody(in: machOFile)),
            image: try required(imageDescriptors.computedSettable.computedPropertyBody(in: machOImage))
        )
    }

    private func check<Value: Equatable>(
        _ accessor: (KeyPathComputedPropertyBody) -> Value,
        _ expectation: Value,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let bodies = try loadBodies()
        let result = try acrossAllReaders(
            file: { accessor(bodies.file) },
            image: { accessor(bodies.image) },
            sourceLocation: sourceLocation
        )
        #expect(result == expectation, sourceLocation: sourceLocation)
    }

    @Test func header() async throws {
        try check({ $0.header.rawValue }, expected.headerRawValue)
        // The body carries the header it was read under, because that is what
        // gives its identifier word a meaning.
        let bodies = try loadBodies()
        #expect(bodies.file.header.kind == .computed)
        #expect(bodies.file.header.isComputedSettable)
    }

    @Test func offset() async throws {
        try check({ $0.offset }, expected.offset)
    }

    @Test func rawIdentifier() async throws {
        try check({ $0.rawIdentifier }, expected.rawIdentifier)
    }

    @Test func getter() async throws {
        try check({ $0.getter.relativeOffset }, expected.getterRelativeOffset)
    }

    @Test func setter() async throws {
        try check({ $0.setter?.relativeOffset }, expected.setterRelativeOffset)
    }

    @Test func identifierFieldOffset() async throws {
        try check({ $0.identifierFieldOffset }, expected.identifierFieldOffset)
        // The identifier is the body's first word.
        let bodies = try loadBodies()
        #expect(bodies.file.identifierFieldOffset == bodies.file.offset)
    }

    @Test func getterFieldOffset() async throws {
        try check({ $0.getterFieldOffset }, expected.getterFieldOffset)
    }

    @Test func setterFieldOffset() async throws {
        try check({ $0.setterFieldOffset }, expected.setterFieldOffset)
    }

    /// The identifier resolves to a location only because this component
    /// identifies its property by pointer; a stored-property or vtable
    /// encoding would report `nil` instead of treating the word as an offset.
    @Test func identifierOffset() async throws {
        try check({ $0.identifierOffset }, expected.identifierOffset)

        let bodies = try loadBodies()
        #expect(bodies.file.header.computedIdentifierKind == .pointer)

        let byStoredProperty = KeyPathComputedPropertyBody(
            header: KeyPathComponentHeader(rawValue: 0x0220_0000),
            offset: bodies.file.offset,
            rawIdentifier: bodies.file.rawIdentifier,
            getter: bodies.file.getter,
            setter: bodies.file.setter
        )
        #expect(byStoredProperty.identifierOffset == nil)
    }

    @Test func getterOffset() async throws {
        try check({ $0.getterOffset }, expected.getterOffset)
    }

    @Test func setterOffset() async throws {
        try check({ $0.setterOffset }, expected.setterOffset)
        // A body with no setter word reports no setter location at all,
        // rather than reading whatever follows the getter.
        let bodies = try loadBodies()
        let getOnly = KeyPathComputedPropertyBody(
            header: KeyPathComponentHeader(rawValue: 0x0200_0000),
            offset: bodies.file.offset,
            rawIdentifier: bodies.file.rawIdentifier,
            getter: bodies.file.getter,
            setter: nil
        )
        #expect(getOnly.setterFieldOffset == nil)
        #expect(getOnly.setterOffset == nil)
    }
}
