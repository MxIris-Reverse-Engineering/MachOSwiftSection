import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `BuiltinType` (the high-level wrapper around
/// `BuiltinTypeDescriptor`).
///
/// Picker: the first `BuiltinTypeDescriptor` from the
/// `__swift5_builtin` section (matches `BuiltinTypeDescriptorBaseline`'s
/// carrier).
@Suite
final class BuiltinTypeTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "BuiltinType"
    static var registeredTestMethodNames: Set<String> {
        BuiltinTypeBaseline.registeredTestMethodNames
    }

    private func loadBuiltins() throws -> (file: BuiltinType, image: BuiltinType) {
        let fileDescriptor = try BaselineFixturePicker.builtinTypeDescriptor_first(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.builtinTypeDescriptor_first(in: machOImage)
        let file = try BuiltinType(descriptor: fileDescriptor, in: machOFile)
        let image = try BuiltinType(descriptor: imageDescriptor, in: machOImage)
        return (file: file, image: image)
    }

    @Test("init(descriptor:in:)") func initializerWithMachO() async throws {
        let fileDescriptor = try BaselineFixturePicker.builtinTypeDescriptor_first(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.builtinTypeDescriptor_first(in: machOImage)

        let fileBuiltin = try BuiltinType(descriptor: fileDescriptor, in: machOFile)
        let imageBuiltin = try BuiltinType(descriptor: imageDescriptor, in: machOImage)
        let fileCtxBuiltin = try BuiltinType(descriptor: fileDescriptor, in: fileContext)
        let imageCtxBuiltin = try BuiltinType(descriptor: imageDescriptor, in: imageContext)

        #expect(fileBuiltin.descriptor.offset == BuiltinTypeBaseline.firstBuiltin.descriptorOffset)
        #expect(imageBuiltin.descriptor.offset == BuiltinTypeBaseline.firstBuiltin.descriptorOffset)
        #expect(fileCtxBuiltin.descriptor.offset == BuiltinTypeBaseline.firstBuiltin.descriptorOffset)
        #expect(imageCtxBuiltin.descriptor.offset == BuiltinTypeBaseline.firstBuiltin.descriptorOffset)
    }

    @Test("init(descriptor:)") func initializerInProcess() async throws {
        // The InProcess `init(descriptor:)` walks the descriptor via raw
        // pointer. We assert it succeeds and the descriptor offset is
        // non-zero (the absolute pointer is per-process).
        let imageDescriptor = try BaselineFixturePicker.builtinTypeDescriptor_first(in: machOImage)
        let pointerWrapper = imageDescriptor.asPointerWrapper(in: machOImage)
        let inProcess = try BuiltinType(descriptor: pointerWrapper)
        #expect(inProcess.descriptor.offset != 0)
    }

    @Test func descriptor() async throws {
        let builtins = try loadBuiltins()
        let result = try acrossAllReaders(
            file: { builtins.file.descriptor.offset },
            image: { builtins.image.descriptor.offset }
        )
        #expect(result == BuiltinTypeBaseline.firstBuiltin.descriptorOffset)
    }

    @Test func typeName() async throws {
        let builtins = try loadBuiltins()
        let presence = try acrossAllReaders(
            file: { builtins.file.typeName != nil },
            image: { builtins.image.typeName != nil }
        )
        #expect(presence == BuiltinTypeBaseline.firstBuiltin.hasTypeName)
    }
}
