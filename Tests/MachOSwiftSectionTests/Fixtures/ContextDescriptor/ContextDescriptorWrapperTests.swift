import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `ContextDescriptorWrapper`.
///
/// `ContextDescriptorWrapper` is the 6-case sum type covering every kind of
/// context descriptor. We exercise it against the `Structs.StructTest`
/// representative — an `isStruct: true` instance, every other `is*`
/// accessor `false`, `hasTypeContextDescriptor: true`, etc. Broader kind
/// coverage lives in the dedicated concrete-kind Suites in Tasks 7-11.
@Suite
final class ContextDescriptorWrapperTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "ContextDescriptorWrapper"
    static var registeredTestMethodNames: Set<String> {
        ContextDescriptorWrapperBaseline.registeredTestMethodNames
    }

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
        let presence = try acrossAllReaders(
            file: { wrappers.file.protocolDescriptor != nil },
            image: { wrappers.image.protocolDescriptor != nil }
        )
        #expect(presence == ContextDescriptorWrapperBaseline.structTest.hasProtocolDescriptor)
    }

    @Test func extensionContextDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(
            file: { wrappers.file.extensionContextDescriptor != nil },
            image: { wrappers.image.extensionContextDescriptor != nil }
        )
        #expect(presence == ContextDescriptorWrapperBaseline.structTest.hasExtensionContextDescriptor)
    }

    @Test func opaqueTypeDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(
            file: { wrappers.file.opaqueTypeDescriptor != nil },
            image: { wrappers.image.opaqueTypeDescriptor != nil }
        )
        #expect(presence == ContextDescriptorWrapperBaseline.structTest.hasOpaqueTypeDescriptor)
    }

    @Test func moduleContextDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(
            file: { wrappers.file.moduleContextDescriptor != nil },
            image: { wrappers.image.moduleContextDescriptor != nil }
        )
        #expect(presence == ContextDescriptorWrapperBaseline.structTest.hasModuleContextDescriptor)
    }

    @Test func anonymousContextDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(
            file: { wrappers.file.anonymousContextDescriptor != nil },
            image: { wrappers.image.anonymousContextDescriptor != nil }
        )
        #expect(presence == ContextDescriptorWrapperBaseline.structTest.hasAnonymousContextDescriptor)
    }

    // MARK: - Boolean predicates

    @Test func isType() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(
            file: { wrappers.file.isType },
            image: { wrappers.image.isType }
        )
        #expect(result == ContextDescriptorWrapperBaseline.structTest.isType)
    }

    @Test func isEnum() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(
            file: { wrappers.file.isEnum },
            image: { wrappers.image.isEnum }
        )
        #expect(result == ContextDescriptorWrapperBaseline.structTest.isEnum)
    }

    @Test func isStruct() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(
            file: { wrappers.file.isStruct },
            image: { wrappers.image.isStruct }
        )
        #expect(result == ContextDescriptorWrapperBaseline.structTest.isStruct)
    }

    @Test func isClass() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(
            file: { wrappers.file.isClass },
            image: { wrappers.image.isClass }
        )
        #expect(result == ContextDescriptorWrapperBaseline.structTest.isClass)
    }

    @Test func isProtocol() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(
            file: { wrappers.file.isProtocol },
            image: { wrappers.image.isProtocol }
        )
        #expect(result == ContextDescriptorWrapperBaseline.structTest.isProtocol)
    }

    @Test func isAnonymous() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(
            file: { wrappers.file.isAnonymous },
            image: { wrappers.image.isAnonymous }
        )
        #expect(result == ContextDescriptorWrapperBaseline.structTest.isAnonymous)
    }

    @Test func isExtension() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(
            file: { wrappers.file.isExtension },
            image: { wrappers.image.isExtension }
        )
        #expect(result == ContextDescriptorWrapperBaseline.structTest.isExtension)
    }

    @Test func isModule() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(
            file: { wrappers.file.isModule },
            image: { wrappers.image.isModule }
        )
        #expect(result == ContextDescriptorWrapperBaseline.structTest.isModule)
    }

    @Test func isOpaqueType() async throws {
        let wrappers = try loadStructTestWrappers()
        let result = try acrossAllReaders(
            file: { wrappers.file.isOpaqueType },
            image: { wrappers.image.isOpaqueType }
        )
        #expect(result == ContextDescriptorWrapperBaseline.structTest.isOpaqueType)
    }

    // MARK: - Alternate-projection vars

    @Test func contextDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        // `contextDescriptor` returns `any ContextDescriptorProtocol`; the
        // `offset` is the cross-reader-stable scalar.
        let result = try acrossAllReaders(
            file: { wrappers.file.contextDescriptor.offset },
            image: { wrappers.image.contextDescriptor.offset }
        )
        #expect(result == ContextDescriptorWrapperBaseline.structTest.descriptorOffset)
    }

    @Test func namedContextDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(
            file: { wrappers.file.namedContextDescriptor != nil },
            image: { wrappers.image.namedContextDescriptor != nil }
        )
        #expect(presence == ContextDescriptorWrapperBaseline.structTest.hasNamedContextDescriptor)
    }

    @Test func typeContextDescriptor() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(
            file: { wrappers.file.typeContextDescriptor != nil },
            image: { wrappers.image.typeContextDescriptor != nil }
        )
        #expect(presence == ContextDescriptorWrapperBaseline.structTest.hasTypeContextDescriptor)
    }

    @Test func typeContextDescriptorWrapper() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(
            file: { wrappers.file.typeContextDescriptorWrapper != nil },
            image: { wrappers.image.typeContextDescriptorWrapper != nil }
        )
        #expect(presence == ContextDescriptorWrapperBaseline.structTest.hasTypeContextDescriptorWrapper)
    }

    // MARK: - Methods

    @Test func parent() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(
            file: { (try wrappers.file.parent(in: machOFile)) != nil },
            image: { (try wrappers.image.parent(in: machOImage)) != nil }
        )
        #expect(presence == ContextDescriptorWrapperBaseline.structTest.hasParent)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try wrappers.image.parent(in: imageContext)) != nil
        #expect(imageCtxPresence == ContextDescriptorWrapperBaseline.structTest.hasParent)
    }

    @Test func genericContext() async throws {
        let wrappers = try loadStructTestWrappers()
        let presence = try acrossAllReaders(
            file: { (try wrappers.file.genericContext(in: machOFile)) != nil },
            image: { (try wrappers.image.genericContext(in: machOImage)) != nil }
        )
        #expect(presence == ContextDescriptorWrapperBaseline.structTest.hasGenericContext)

        // ReadingContext-based overload also exercised.
        let imageCtxPresence = (try wrappers.image.genericContext(in: imageContext)) != nil
        #expect(imageCtxPresence == ContextDescriptorWrapperBaseline.structTest.hasGenericContext)
    }

    @Test func resolve() async throws {
        // `resolve` is a static func with multiple overloads; all collapse to
        // one MethodKey. Exercise the MachO-based overload that returns
        // `Self` (the path used by `ContextDescriptorWrapper.resolve(from:in:)`
        // when reading wrapper records out of a section). Type the result
        // explicitly as `ContextDescriptorWrapper` to disambiguate from the
        // `Self?`-returning sibling overload.
        let fileDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.struct_StructTest(in: machOImage)

        let fileWrapper: ContextDescriptorWrapper = try ContextDescriptorWrapper.resolve(from: fileDescriptor.offset, in: machOFile)
        let imageWrapper: ContextDescriptorWrapper = try ContextDescriptorWrapper.resolve(from: imageDescriptor.offset, in: machOImage)

        #expect(fileWrapper.isStruct == true)
        #expect(imageWrapper.isStruct == true)
        #expect(fileWrapper.contextDescriptor.offset == ContextDescriptorWrapperBaseline.structTest.descriptorOffset)
        #expect(imageWrapper.contextDescriptor.offset == ContextDescriptorWrapperBaseline.structTest.descriptorOffset)
    }
}
