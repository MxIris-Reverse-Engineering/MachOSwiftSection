import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `KeyPathComponentHeader`.
///
/// The header is one word of bit arithmetic, so every accessor is asserted
/// against the baseline for the four live descriptors, plus three synthesized
/// words covering what a property descriptor structurally cannot carry: an
/// `optional` component, an `external` one with substitution arguments, and
/// the end-of-reference-prefix flag. Those three only ever occur inside a key
/// path pattern, and the header models the pattern encoding too (evolution
/// proposal 0025).
@Suite
final class KeyPathComponentHeaderTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "KeyPathComponentHeader"
    static var registeredTestMethodNames: Set<String> {
        KeyPathComponentHeaderBaseline.registeredTestMethodNames
    }

    private struct Shape {
        let label: String
        let file: KeyPathComponentHeader
        let image: KeyPathComponentHeader
        let expected: KeyPathComponentHeaderBaseline.Entry
    }

    /// The four headers read out of the fixture, each across both readers.
    private func liveShapes() throws -> [Shape] {
        let fileDescriptors = try KeyPathFixtureDescriptors(in: machOFile)
        let imageDescriptors = try KeyPathFixtureDescriptors(in: machOImage)
        return [
            Shape(label: "trivial", file: fileDescriptors.trivial.header, image: imageDescriptors.trivial.header, expected: KeyPathComponentHeaderBaseline.trivial),
            Shape(label: "inlineStoredOffset", file: fileDescriptors.inlineStoredOffset.header, image: imageDescriptors.inlineStoredOffset.header, expected: KeyPathComponentHeaderBaseline.inlineStoredOffset),
            Shape(label: "unresolvedFieldOffset", file: fileDescriptors.unresolvedFieldOffset.header, image: imageDescriptors.unresolvedFieldOffset.header, expected: KeyPathComponentHeaderBaseline.unresolvedFieldOffset),
            Shape(label: "computedSettable", file: fileDescriptors.computedSettable.header, image: imageDescriptors.computedSettable.header, expected: KeyPathComponentHeaderBaseline.computedSettable),
        ]
    }

    /// The three pattern-only words, rebuilt from their recorded raw value so
    /// the pattern-side accessors are covered even though no property
    /// descriptor can carry them.
    private func synthesizedShapes() -> [(label: String, header: KeyPathComponentHeader, expected: KeyPathComponentHeaderBaseline.Entry)] {
        [
            ("optionalChain", KeyPathComponentHeader(rawValue: KeyPathComponentHeaderBaseline.synthesizedOptionalChain.rawValue), KeyPathComponentHeaderBaseline.synthesizedOptionalChain),
            ("externalWithTwoArguments", KeyPathComponentHeader(rawValue: KeyPathComponentHeaderBaseline.synthesizedExternalWithTwoArguments.rawValue), KeyPathComponentHeaderBaseline.synthesizedExternalWithTwoArguments),
            ("endOfReferencePrefix", KeyPathComponentHeader(rawValue: KeyPathComponentHeaderBaseline.synthesizedEndOfReferencePrefix.rawValue), KeyPathComponentHeaderBaseline.synthesizedEndOfReferencePrefix),
        ]
    }

    /// Asserts a header accessor across both readers for the live shapes, and
    /// directly for the synthesized ones.
    private func check<Value: Equatable>(
        _ accessor: (KeyPathComponentHeader) -> Value,
        _ expectation: (KeyPathComponentHeaderBaseline.Entry) -> Value,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        for shape in try liveShapes() {
            let result = try acrossAllReaders(
                file: { accessor(shape.file) },
                image: { accessor(shape.image) },
                sourceLocation: sourceLocation
            )
            #expect(result == expectation(shape.expected), "\(shape.label)", sourceLocation: sourceLocation)
        }
        for shape in synthesizedShapes() {
            #expect(accessor(shape.header) == expectation(shape.expected), "\(shape.label)", sourceLocation: sourceLocation)
        }
    }

    @Test func rawValue() async throws {
        try check({ $0.rawValue }, { $0.rawValue })
    }

    @Test("init(rawValue:)") func initializerWithRawValue() async throws {
        let entry = KeyPathComponentHeaderBaseline.computedSettable
        let constructed = KeyPathComponentHeader(rawValue: entry.rawValue)
        #expect(constructed.rawValue == entry.rawValue)
        #expect(constructed.rawKind == entry.rawKind)
        #expect(constructed.isComputedSettable == entry.isComputedSettable)
        #expect(constructed.propertyDescriptorBodySize == entry.propertyDescriptorBodySize)
    }

    @Test func rawKind() async throws {
        try check({ $0.rawKind }, { $0.rawKind })
    }

    @Test func kind() async throws {
        try check({ String(describing: $0.kind) }, { $0.kindDescription })
        // A discriminator the runtime does not define must read as `nil`
        // rather than force-unwrapping into a crash: the field is 7 bits
        // wide and the input is arbitrary binary content.
        #expect(KeyPathComponentHeader(rawValue: 0x0500_0000).kind == nil)
        #expect(KeyPathComponentHeader(rawValue: 0x7F00_0000).kind == nil)
    }

    @Test func payload() async throws {
        try check({ $0.payload }, { $0.payload })
    }

    @Test func isTrivialPropertyDescriptor() async throws {
        try check({ $0.isTrivialPropertyDescriptor }, { $0.isTrivialPropertyDescriptor })
    }

    @Test func isEndOfReferencePrefix() async throws {
        try check({ $0.isEndOfReferencePrefix }, { $0.isEndOfReferencePrefix })
    }

    @Test func storedOffsetPayload() async throws {
        try check({ $0.storedOffsetPayload }, { $0.storedOffsetPayload })
    }

    @Test func isStoredMutable() async throws {
        try check({ $0.isStoredMutable }, { $0.isStoredMutable })
    }

    @Test func storedFieldOffsetKind() async throws {
        try check({ String(describing: $0.storedFieldOffsetKind) }, { $0.storedFieldOffsetKindDescription })
        // The three sentinel payloads must each classify distinctly — they
        // all mean "the body carries a word", but not the same word.
        #expect(KeyPathComponentHeader(rawValue: 0x0100_0000 | 0x007F_FFFF).storedFieldOffsetKind == .outOfLine)
        #expect(KeyPathComponentHeader(rawValue: 0x0100_0000 | 0x007F_FFFE).storedFieldOffsetKind == .unresolvedFieldOffset)
        #expect(KeyPathComponentHeader(rawValue: 0x0100_0000 | 0x007F_FFFD).storedFieldOffsetKind == .unresolvedIndirectOffset)
        #expect(KeyPathComponentHeader(rawValue: 0x0100_0000 | 0x007F_FFFC).storedFieldOffsetKind == .inline)
        // A class component classifies the same way a struct one does.
        #expect(KeyPathComponentHeader(rawValue: 0x0300_0000 | 0x007F_FFFE).storedFieldOffsetKind == .unresolvedFieldOffset)
    }

    @Test func inlineStoredFieldOffset() async throws {
        try check({ $0.inlineStoredFieldOffset }, { $0.inlineStoredFieldOffset })
    }

    @Test func isComputedSettable() async throws {
        try check({ $0.isComputedSettable }, { $0.isComputedSettable })
    }

    @Test func isComputedMutating() async throws {
        try check({ $0.isComputedMutating }, { $0.isComputedMutating })
    }

    @Test func hasComputedArguments() async throws {
        try check({ $0.hasComputedArguments }, { $0.hasComputedArguments })
    }

    @Test func computedIdentifierKind() async throws {
        try check({ String(describing: $0.computedIdentifierKind) }, { $0.computedIdentifierKindDescription })
        #expect(KeyPathComponentHeader(rawValue: 0x0220_0000).computedIdentifierKind == .storedPropertyOffset)
        #expect(KeyPathComponentHeader(rawValue: 0x0210_0000).computedIdentifierKind == .vtableOffset)
        #expect(KeyPathComponentHeader(rawValue: 0x0200_0000).computedIdentifierKind == .pointer)
    }

    @Test func computedIdentifierResolution() async throws {
        try check({ $0.computedIdentifierResolution?.rawValue }, { $0.computedIdentifierResolutionRawValue })
        #expect(KeyPathComponentHeader(rawValue: 0x0200_0001).computedIdentifierResolution == .unresolvedFunctionCall)
        #expect(KeyPathComponentHeader(rawValue: 0x0200_0002).computedIdentifierResolution == .unresolvedIndirectPointer)
        #expect(KeyPathComponentHeader(rawValue: 0x0200_0003).computedIdentifierResolution == .resolvedAbsolute)
        // A value outside the defined set reads as `nil`, not a fabricated case.
        #expect(KeyPathComponentHeader(rawValue: 0x0200_0004).computedIdentifierResolution == nil)
    }

    @Test func optionalComponentKind() async throws {
        try check({ String(describing: $0.optionalComponentKind) }, { $0.optionalComponentKindDescription })
        #expect(KeyPathComponentHeader(rawValue: 0x0400_0000).optionalComponentKind == .chain)
        #expect(KeyPathComponentHeader(rawValue: 0x0400_0001).optionalComponentKind == .wrap)
        #expect(KeyPathComponentHeader(rawValue: 0x0400_0002).optionalComponentKind == .force)
        // Not an optional component at all.
        #expect(KeyPathComponentHeader(rawValue: 0x0100_0000).optionalComponentKind == nil)
    }

    @Test func propertyDescriptorBodySize() async throws {
        try check({ $0.propertyDescriptorBodySize }, { $0.propertyDescriptorBodySize })
    }

    /// The pattern-side length differs from the property-descriptor one in
    /// exactly two places: a zero word is an ordinary `external` component
    /// there (4 bytes of body, not the trivial marker's zero), and a computed
    /// component with arguments carries 12 more bytes a descriptor never has.
    @Test func patternComponentBodySize() async throws {
        try check({ $0.patternComponentBodySize }, { $0.patternComponentBodySize })

        let trivialMarker = KeyPathComponentHeader(rawValue: 0)
        #expect(trivialMarker.propertyDescriptorBodySize == 0)
        #expect(trivialMarker.patternComponentBodySize == 4)

        let computedWithArguments = KeyPathComponentHeader(rawValue: 0x0200_0000 | 0x0040_0000 | 0x0008_0000)
        #expect(computedWithArguments.propertyDescriptorBodySize == 12)
        #expect(computedWithArguments.patternComponentBodySize == 24)
    }
}
