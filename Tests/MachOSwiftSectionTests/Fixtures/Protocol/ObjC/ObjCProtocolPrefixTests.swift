import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ObjCProtocolPrefix`.
///
/// We materialize an ObjC prefix via the fixture's
/// `Protocols.ObjCInheritingProtocolTest: NSObjectProtocol` requirement,
/// which surfaces an `ObjCProtocolPrefix` resolving to `NSObject`.
@Suite
final class ObjCProtocolPrefixTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ObjCProtocolPrefix"
    static var registeredTestMethodNames: Set<String> {
        ObjCProtocolPrefixBaseline.registeredTestMethodNames
    }

    private func loadFirstPrefixes() throws -> (file: ObjCProtocolPrefix, image: ObjCProtocolPrefix) {
        let file = try BaselineFixturePicker.objcProtocolPrefix_first(in: machOFile)
        let image = try BaselineFixturePicker.objcProtocolPrefix_first(in: machOImage)
        return (file: file, image: image)
    }

    /// `ObjCProtocolPrefix.offset` reflects the resolved location of the
    /// prefix in the loaded image. For MachOFile, that's the file offset
    /// stored at the picker resolution time. For MachOImage, the prefix
    /// lives in dyld's runtime address space and the value diverges
    /// between the two readers — we assert the file-side offset matches
    /// the baseline and verify both reader code paths are reachable.
    @Test func offset() async throws {
        let (file, image) = try loadFirstPrefixes()
        #expect(file.offset == ObjCProtocolPrefixBaseline.firstPrefix.offset)
        // The image offset is a runtime memory address, not an image-
        // relative file offset; just verify the read returns a non-zero
        // value (the ObjC prefix is always non-null when the inheriting
        // protocol resolves successfully).
        #expect(image.offset != 0)
    }

    @Test func layout() async throws {
        let (file, _) = try loadFirstPrefixes()
        // The layout carries `isa` (raw pointer) and `name` (Pointer<String>);
        // the name resolution is exercised below.
        _ = file.layout.isa
        _ = file.layout.name
    }

    @Test func name() async throws {
        let (file, image) = try loadFirstPrefixes()
        let result = try acrossAllReaders(
            file: { try file.name(in: machOFile) },
            image: { try image.name(in: machOImage) }
        )
        #expect(result == ObjCProtocolPrefixBaseline.firstPrefix.name)

        // ReadingContext overload also exercised.
        let imageContextResult = try image.name(in: imageContext)
        #expect(imageContextResult == ObjCProtocolPrefixBaseline.firstPrefix.name)
    }

    @Test func mangledName() async throws {
        // `mangledName(in:)` returns a MangledName payload; we exercise
        // its accessibility and ensure it resolves without error.
        let (file, image) = try loadFirstPrefixes()
        _ = try file.mangledName(in: machOFile)
        _ = try image.mangledName(in: machOImage)
        _ = try image.mangledName(in: imageContext)
    }
}
