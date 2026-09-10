import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `KeyPathStoredFieldOffset`.
///
/// Two of the four fixture descriptors are stored ones and they land on
/// different cases: a non-generic struct's offset is a constant in the header
/// (`inline`), a generic struct's is only a pointer INTO the metadata
/// (`unresolvedFieldOffset`). That distinction is what `staticFieldOffset`
/// exists to make, so both are asserted here. The two remaining cases have no
/// fixture carrier and are constructed directly.
@Suite
final class KeyPathStoredFieldOffsetTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "KeyPathStoredFieldOffset"
    static var registeredTestMethodNames: Set<String> {
        KeyPathStoredFieldOffsetBaseline.registeredTestMethodNames
    }

    private struct Shape {
        let label: String
        let file: KeyPathStoredFieldOffset
        let image: KeyPathStoredFieldOffset
        let expected: KeyPathStoredFieldOffsetBaseline.Entry
    }

    private func liveShapes() throws -> [Shape] {
        let fileDescriptors = try KeyPathFixtureDescriptors(in: machOFile)
        let imageDescriptors = try KeyPathFixtureDescriptors(in: machOImage)
        return [
            Shape(
                label: "inlineStoredOffset",
                file: try required(fileDescriptors.inlineStoredOffset.storedFieldOffset(in: machOFile)),
                image: try required(imageDescriptors.inlineStoredOffset.storedFieldOffset(in: machOImage)),
                expected: KeyPathStoredFieldOffsetBaseline.inlineStoredOffset
            ),
            Shape(
                label: "unresolvedFieldOffset",
                file: try required(fileDescriptors.unresolvedFieldOffset.storedFieldOffset(in: machOFile)),
                image: try required(imageDescriptors.unresolvedFieldOffset.storedFieldOffset(in: machOImage)),
                expected: KeyPathStoredFieldOffsetBaseline.unresolvedFieldOffset
            ),
        ]
    }

    private func synthesizedShapes() -> [(label: String, value: KeyPathStoredFieldOffset, expected: KeyPathStoredFieldOffsetBaseline.Entry)] {
        [
            ("outOfLine", .outOfLine(KeyPathStoredFieldOffsetBaseline.synthesizedOutOfLine.rawValue), KeyPathStoredFieldOffsetBaseline.synthesizedOutOfLine),
            (
                "unresolvedIndirectOffset",
                .unresolvedIndirectOffset(offsetOfFieldOffsetPointer: KeyPathStoredFieldOffsetBaseline.synthesizedUnresolvedIndirectOffset.rawValue),
                KeyPathStoredFieldOffsetBaseline.synthesizedUnresolvedIndirectOffset
            ),
        ]
    }

    private func check<Value: Equatable>(
        _ accessor: (KeyPathStoredFieldOffset) -> Value,
        _ expectation: (KeyPathStoredFieldOffsetBaseline.Entry) -> Value,
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
            #expect(accessor(shape.value) == expectation(shape.expected), "\(shape.label)", sourceLocation: sourceLocation)
        }
    }

    @Test func kind() async throws {
        try check({ String(describing: $0.kind) }, { $0.kindDescription })
    }

    @Test func rawValue() async throws {
        try check({ $0.rawValue }, { $0.rawValue })
    }

    /// The whole point of the type: an offset the binary states outright
    /// versus one that can only be read out of live metadata.
    @Test func staticFieldOffset() async throws {
        try check({ $0.staticFieldOffset }, { $0.staticFieldOffset })

        #expect(KeyPathStoredFieldOffset.inline(0x10).staticFieldOffset == 0x10)
        #expect(KeyPathStoredFieldOffset.outOfLine(0x800000).staticFieldOffset == 0x800000)
        #expect(KeyPathStoredFieldOffset.unresolvedFieldOffset(offsetOfFieldOffset: 0x20).staticFieldOffset == nil)
        #expect(KeyPathStoredFieldOffset.unresolvedIndirectOffset(offsetOfFieldOffsetPointer: 0x20).staticFieldOffset == nil)
    }
}
