import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `ExtensionContext` (the high-level wrapper
/// around `ExtensionContextDescriptor`).
///
/// Extensions in `SymbolTestsCore` are discovered via the parent chain of
/// type descriptors — they don't appear directly in
/// `__swift5_types`/`__swift5_types2` records. The optional `genericContext`
/// and `extendedContextMangledName` ivars use the presence-flag pattern.
@Suite
@FixtureSuite
final class ExtensionContextTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    /// Helper: instantiate the `ExtensionContext` wrapper for the
    /// fixture's first extension descriptor against both readers.
    private func loadFirstExtensionContexts() throws -> (file: ExtensionContext, image: ExtensionContext) {
        let fileDescriptor = try BaselineFixturePicker.extension_first(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.extension_first(in: machOImage)
        let file = try ExtensionContext(descriptor: fileDescriptor, in: fileContext)
        let image = try ExtensionContext(descriptor: imageDescriptor, in: imageContext)
        return (file: file, image: image)
    }

    // MARK: - Initializers

    @Test("init(descriptor:in:)") func initializerWithMachO() async throws {
        let fileDescriptor = try BaselineFixturePicker.extension_first(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.extension_first(in: machOImage)

        let fileContext_ = try ExtensionContext(descriptor: fileDescriptor, in: fileContext)
        let imageContext_ = try ExtensionContext(descriptor: imageDescriptor, in: imageContext)

        #expect(fileContext_.descriptor.offset == ExtensionContextBaseline.firstExtension.descriptorOffset)
        #expect(imageContext_.descriptor.offset == ExtensionContextBaseline.firstExtension.descriptorOffset)
    }

    @Test("init(descriptor:)") func initializerInProcess() async throws {
        let imageDescriptor = try BaselineFixturePicker.extension_first(in: machOImage)
        let pointerDescriptor = imageDescriptor.asPointerWrapper(in: machOImage)
        let inProcessContext_ = try ExtensionContext(descriptor: pointerDescriptor, in: inProcessContext)

        #expect(inProcessContext_.descriptor.offset != 0)
    }

    // MARK: - Ivars

    @Test func descriptor() async throws {
        let contexts = try loadFirstExtensionContexts()
        let descriptorOffsets = try acrossAllReaders(contexts.file, contexts.image) { $0.descriptor.offset }
        #expect(descriptorOffsets == ExtensionContextBaseline.firstExtension.descriptorOffset)
    }

    @Test func genericContext() async throws {
        let contexts = try loadFirstExtensionContexts()
        let presence = try acrossAllReaders(contexts.file, contexts.image) { $0.genericContext != nil }
        #expect(presence == ExtensionContextBaseline.firstExtension.hasGenericContext)
    }

    @Test func extendedContextMangledName() async throws {
        let contexts = try loadFirstExtensionContexts()
        let presence = try acrossAllReaders(contexts.file, contexts.image) { $0.extendedContextMangledName != nil }
        #expect(presence == ExtensionContextBaseline.firstExtension.hasExtendedContextMangledName)
    }
}
