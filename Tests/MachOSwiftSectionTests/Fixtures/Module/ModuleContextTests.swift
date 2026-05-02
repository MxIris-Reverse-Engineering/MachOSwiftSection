import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ModuleContext` (the high-level wrapper around
/// `ModuleContextDescriptor`).
///
/// `ModuleContext` only carries `descriptor` and `name`; `name` is a
/// stable string literal we embed in the baseline.
@Suite
final class ModuleContextTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ModuleContext"
    static var registeredTestMethodNames: Set<String> {
        ModuleContextBaseline.registeredTestMethodNames
    }

    /// Helper: instantiate the `ModuleContext` wrapper for the
    /// `SymbolTestsCore` module against both readers.
    private func loadSymbolTestsCoreContexts() throws -> (file: ModuleContext, image: ModuleContext) {
        let fileDescriptor = try BaselineFixturePicker.module_SymbolTestsCore(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.module_SymbolTestsCore(in: machOImage)
        let file = try ModuleContext(descriptor: fileDescriptor, in: machOFile)
        let image = try ModuleContext(descriptor: imageDescriptor, in: machOImage)
        return (file: file, image: image)
    }

    // MARK: - Initializers

    @Test("init(descriptor:in:)") func initializerWithMachO() async throws {
        let fileDescriptor = try BaselineFixturePicker.module_SymbolTestsCore(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.module_SymbolTestsCore(in: machOImage)

        let fileContext_ = try ModuleContext(descriptor: fileDescriptor, in: machOFile)
        let imageContext_ = try ModuleContext(descriptor: imageDescriptor, in: machOImage)
        let fileCtxContext = try ModuleContext(descriptor: fileDescriptor, in: fileContext)
        let imageCtxContext = try ModuleContext(descriptor: imageDescriptor, in: imageContext)

        #expect(fileContext_.descriptor.offset == ModuleContextBaseline.symbolTestsCore.descriptorOffset)
        #expect(imageContext_.descriptor.offset == ModuleContextBaseline.symbolTestsCore.descriptorOffset)
        #expect(fileCtxContext.descriptor.offset == ModuleContextBaseline.symbolTestsCore.descriptorOffset)
        #expect(imageCtxContext.descriptor.offset == ModuleContextBaseline.symbolTestsCore.descriptorOffset)
        #expect(fileContext_.name == ModuleContextBaseline.symbolTestsCore.name)
    }

    @Test("init(descriptor:)") func initializerInProcess() async throws {
        let imageDescriptor = try BaselineFixturePicker.module_SymbolTestsCore(in: machOImage)
        let pointerDescriptor = imageDescriptor.asPointerWrapper(in: machOImage)
        let inProcessContext_ = try ModuleContext(descriptor: pointerDescriptor)

        #expect(inProcessContext_.descriptor.offset != 0)
        #expect(inProcessContext_.name == ModuleContextBaseline.symbolTestsCore.name)
    }

    // MARK: - Ivars

    @Test func descriptor() async throws {
        let contexts = try loadSymbolTestsCoreContexts()
        let descriptorOffsets = try acrossAllReaders(
            file: { contexts.file.descriptor.offset },
            image: { contexts.image.descriptor.offset }
        )
        #expect(descriptorOffsets == ModuleContextBaseline.symbolTestsCore.descriptorOffset)
    }

    @Test func name() async throws {
        let contexts = try loadSymbolTestsCoreContexts()
        let result = try acrossAllReaders(
            file: { contexts.file.name },
            image: { contexts.image.name }
        )
        #expect(result == ModuleContextBaseline.symbolTestsCore.name)
    }
}
