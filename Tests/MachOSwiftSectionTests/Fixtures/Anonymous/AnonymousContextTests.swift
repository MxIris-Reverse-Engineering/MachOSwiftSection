import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `AnonymousContext` (the high-level wrapper
/// around `AnonymousContextDescriptor`).
///
/// Anonymous contexts in `SymbolTestsCore` arise from generic parameter
/// scopes and other unnamed contexts; they're discovered via the parent
/// chain of generic types, not via top-level `__swift5_types` records.
///
/// `init(descriptor:in:)` (MachO + ReadingContext overloads) and
/// `init(descriptor:)` (in-process) are covered by dedicated tests; the
/// other ivars use the established presence-flag pattern (`MangledName`
/// and `GenericContext` aren't cheaply Equatable).
@Suite
final class AnonymousContextTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "AnonymousContext"
    static var registeredTestMethodNames: Set<String> {
        AnonymousContextBaseline.registeredTestMethodNames
    }

    /// Helper: instantiate the `AnonymousContext` wrapper using the
    /// MachO-direct initializer for both readers.
    private func loadFirstAnonymousContexts() throws -> (file: AnonymousContext, image: AnonymousContext) {
        let fileDescriptor = try BaselineFixturePicker.anonymous_first(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.anonymous_first(in: machOImage)
        let file = try AnonymousContext(descriptor: fileDescriptor, in: machOFile)
        let image = try AnonymousContext(descriptor: imageDescriptor, in: machOImage)
        return (file: file, image: image)
    }

    // MARK: - Initializers

    @Test("init(descriptor:in:)") func initializerWithMachO() async throws {
        let fileDescriptor = try BaselineFixturePicker.anonymous_first(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.anonymous_first(in: machOImage)

        // Both file/image MachO-based initializers must succeed and produce
        // a descriptor whose offset matches the baseline. The
        // ReadingContext-based overload also exists.
        let fileContext_ = try AnonymousContext(descriptor: fileDescriptor, in: machOFile)
        let imageContext_ = try AnonymousContext(descriptor: imageDescriptor, in: machOImage)
        let fileCtxContext = try AnonymousContext(descriptor: fileDescriptor, in: fileContext)
        let imageCtxContext = try AnonymousContext(descriptor: imageDescriptor, in: imageContext)

        #expect(fileContext_.descriptor.offset == AnonymousContextBaseline.firstAnonymous.descriptorOffset)
        #expect(imageContext_.descriptor.offset == AnonymousContextBaseline.firstAnonymous.descriptorOffset)
        #expect(fileCtxContext.descriptor.offset == AnonymousContextBaseline.firstAnonymous.descriptorOffset)
        #expect(imageCtxContext.descriptor.offset == AnonymousContextBaseline.firstAnonymous.descriptorOffset)
    }

    @Test("init(descriptor:)") func initializerInProcess() async throws {
        // The InProcess `init(descriptor:)` requires a pointer-form
        // descriptor resolved against MachOImage; reproduce that here.
        let imageDescriptor = try BaselineFixturePicker.anonymous_first(in: machOImage)
        let pointerDescriptor = imageDescriptor.asPointerWrapper(in: machOImage)
        let inProcessContext_ = try AnonymousContext(descriptor: pointerDescriptor)

        // The in-process `descriptor.offset` is a pointer bit pattern, not
        // a file offset — we just assert it resolved.
        #expect(inProcessContext_.descriptor.offset != 0)
    }

    // MARK: - Ivars

    @Test func descriptor() async throws {
        let contexts = try loadFirstAnonymousContexts()
        let descriptorOffsets = try acrossAllReaders(
            file: { contexts.file.descriptor.offset },
            image: { contexts.image.descriptor.offset }
        )
        #expect(descriptorOffsets == AnonymousContextBaseline.firstAnonymous.descriptorOffset)
    }

    @Test func genericContext() async throws {
        let contexts = try loadFirstAnonymousContexts()
        let presence = try acrossAllReaders(
            file: { contexts.file.genericContext != nil },
            image: { contexts.image.genericContext != nil }
        )
        #expect(presence == AnonymousContextBaseline.firstAnonymous.hasGenericContext)
    }

    @Test func mangledName() async throws {
        let contexts = try loadFirstAnonymousContexts()
        let presence = try acrossAllReaders(
            file: { contexts.file.mangledName != nil },
            image: { contexts.image.mangledName != nil }
        )
        #expect(presence == AnonymousContextBaseline.firstAnonymous.hasMangledName)
    }
}
