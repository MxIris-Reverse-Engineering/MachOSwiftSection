import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftSectionTestingSupport
import SwiftSectionFixtureSupport

/// Fixture-based Suite for `ContextDescriptorWrapper`.
///
/// `ContextDescriptorWrapper` is the 6-case sum type covering every kind of
/// context descriptor. We exercise it against the `Structs.StructTest`
/// representative — an `isStruct: true` instance, every other `is*`
/// accessor `false`, `hasTypeContextDescriptor: true`, etc. Broader kind
/// coverage lives in the dedicated concrete-kind Suites in Tasks 7-11.
@Suite
@FixtureSuite
final class ContextDescriptorWrapperTests: MachOSwiftSectionFixtureTests, @unchecked Sendable {
    /// Helper: build a `ContextDescriptorWrapper` of the
    /// `Structs.StructTest` descriptor against both readers.
    private func loadStructTestWrappers() throws -> (file: ContextDescriptorWrapper, image: ContextDescriptorWrapper) {
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)
        return (file: .type(.struct(fileDescriptor)), image: .type(.struct(imageDescriptor)))
    }

    // MARK: - Case-extraction accessors

    @Test func protocolDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(wrappers.file, wrappers.image) { $0.protocolDescriptor != nil }
        #expect(presence == ContextDescriptorWrapperBaseline.structTest.hasProtocolDescriptor)
    }

    @Test func extensionContextDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(wrappers.file, wrappers.image) { $0.extensionContextDescriptor != nil }
        #expect(presence == ContextDescriptorWrapperBaseline.structTest.hasExtensionContextDescriptor)
    }

    @Test func opaqueTypeDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(wrappers.file, wrappers.image) { $0.opaqueTypeDescriptor != nil }
        #expect(presence == ContextDescriptorWrapperBaseline.structTest.hasOpaqueTypeDescriptor)
    }

    @Test func moduleContextDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(wrappers.file, wrappers.image) { $0.moduleContextDescriptor != nil }
        #expect(presence == ContextDescriptorWrapperBaseline.structTest.hasModuleContextDescriptor)
    }

    @Test func anonymousContextDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(wrappers.file, wrappers.image) { $0.anonymousContextDescriptor != nil }
        #expect(presence == ContextDescriptorWrapperBaseline.structTest.hasAnonymousContextDescriptor)
    }

    // MARK: - Boolean predicates

    @Test func isType() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(wrappers.file, wrappers.image) { $0.isType }
        #expect(result == ContextDescriptorWrapperBaseline.structTest.isType)
    }

    @Test func isEnum() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(wrappers.file, wrappers.image) { $0.isEnum }
        #expect(result == ContextDescriptorWrapperBaseline.structTest.isEnum)
    }

    @Test func isStruct() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(wrappers.file, wrappers.image) { $0.isStruct }
        #expect(result == ContextDescriptorWrapperBaseline.structTest.isStruct)
    }

    @Test func isClass() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(wrappers.file, wrappers.image) { $0.isClass }
        #expect(result == ContextDescriptorWrapperBaseline.structTest.isClass)
    }

    @Test func isProtocol() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(wrappers.file, wrappers.image) { $0.isProtocol }
        #expect(result == ContextDescriptorWrapperBaseline.structTest.isProtocol)
    }

    @Test func isAnonymous() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(wrappers.file, wrappers.image) { $0.isAnonymous }
        #expect(result == ContextDescriptorWrapperBaseline.structTest.isAnonymous)
    }

    @Test func isExtension() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(wrappers.file, wrappers.image) { $0.isExtension }
        #expect(result == ContextDescriptorWrapperBaseline.structTest.isExtension)
    }

    @Test func isModule() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(wrappers.file, wrappers.image) { $0.isModule }
        #expect(result == ContextDescriptorWrapperBaseline.structTest.isModule)
    }

    @Test func isOpaqueType() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(wrappers.file, wrappers.image) { $0.isOpaqueType }
        #expect(result == ContextDescriptorWrapperBaseline.structTest.isOpaqueType)
    }

    // MARK: - Alternate-projection vars

    @Test func contextDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        // `contextDescriptor` returns `any ContextDescriptorProtocol`; the
        // `offset` is the cross-reader-stable scalar.
        let result = try acrossAllReaders(wrappers.file, wrappers.image) { $0.contextDescriptor.offset }
        #expect(result == ContextDescriptorWrapperBaseline.structTest.descriptorOffset)
    }

    @Test func namedContextDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(wrappers.file, wrappers.image) { $0.namedContextDescriptor != nil }
        #expect(presence == ContextDescriptorWrapperBaseline.structTest.hasNamedContextDescriptor)
    }

    @Test func typeContextDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(wrappers.file, wrappers.image) { $0.typeContextDescriptor != nil }
        #expect(presence == ContextDescriptorWrapperBaseline.structTest.hasTypeContextDescriptor)
    }

    @Test func typeContextDescriptorWrapper() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(wrappers.file, wrappers.image) { $0.typeContextDescriptorWrapper != nil }
        #expect(presence == ContextDescriptorWrapperBaseline.structTest.hasTypeContextDescriptorWrapper)
    }

    // MARK: - Methods

    @Test func parent() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllContexts(wrappers.file, wrappers.image) { wrapper, context in
            (try wrapper.parent(in: context)) != nil
        }
        #expect(presence == ContextDescriptorWrapperBaseline.structTest.hasParent)
    }

    @Test func genericContext() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllContexts(wrappers.file, wrappers.image) { wrapper, context in
            (try wrapper.genericContext(in: context)) != nil
        }
        #expect(presence == ContextDescriptorWrapperBaseline.structTest.hasGenericContext)
    }

    @Test func resolve() async throws {
        // `resolve` is a static func with multiple overloads; all collapse to
        // one MethodKey. Exercise the ReadingContext-based overload that
        // returns `Self` (the path used by `ContextDescriptorWrapper.resolve(at:in:)`
        // when reading wrapper records out of a section). Type the result
        // explicitly as `ContextDescriptorWrapper` to disambiguate from the
        // `Self?`-returning sibling overload.
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        let fileWrapper: ContextDescriptorWrapper = try ContextDescriptorWrapper.resolve(at: fileDescriptor.offset, in: fileContext)
        let imageWrapper: ContextDescriptorWrapper = try ContextDescriptorWrapper.resolve(at: imageDescriptor.offset, in: imageContext)

        #expect(fileWrapper.isStruct == true)
        #expect(imageWrapper.isStruct == true)
        #expect(fileWrapper.contextDescriptor.offset == ContextDescriptorWrapperBaseline.structTest.descriptorOffset)
        #expect(imageWrapper.contextDescriptor.offset == ContextDescriptorWrapperBaseline.structTest.descriptorOffset)
    }
}
