import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

/// Fixture-based Suite for `MethodDescriptorFlags`.
///
/// We extract the live flags from the first vtable entry of
/// `Classes.ClassTest` and assert each derived predicate against the
/// baseline. The first entry in `ClassTest`'s vtable is the
/// `instanceVariable` getter — kind `.getter`, isInstance `true`,
/// other bits clear.
@Suite
final class MethodDescriptorFlagsTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "MethodDescriptorFlags"
    static var registeredTestMethodNames: Set<String> {
        MethodDescriptorFlagsBaseline.registeredTestMethodNames
    }

    /// Helper: load the first vtable entry's flags from each reader.
    private func loadFirstFlags() throws -> (file: MethodDescriptorFlags, image: MethodDescriptorFlags) {
        let fileDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.class_ClassTest(in: machOImage)
        let fileClass = try Class(descriptor: fileDescriptor, in: machOFile)
        let imageClass = try Class(descriptor: imageDescriptor, in: machOImage)
        let fileFlags = try required(fileClass.methodDescriptors.first?.layout.flags)
        let imageFlags = try required(imageClass.methodDescriptors.first?.layout.flags)
        return (file: fileFlags, image: imageFlags)
    }

    @Test func rawValue() async throws {
        let flags = try loadFirstFlags()
        let result = try acrossAllReaders(
            file: { flags.file.rawValue },
            image: { flags.image.rawValue }
        )
        #expect(result == MethodDescriptorFlagsBaseline.firstClassTestMethod.rawValue)
    }

    @Test("init(rawValue:)") func initializerWithRawValue() async throws {
        let constructed = MethodDescriptorFlags(
            rawValue: MethodDescriptorFlagsBaseline.firstClassTestMethod.rawValue
        )
        #expect(constructed.rawValue == MethodDescriptorFlagsBaseline.firstClassTestMethod.rawValue)
        #expect(constructed.kind.rawValue == MethodDescriptorFlagsBaseline.firstClassTestMethod.kindRawValue)
        #expect(constructed.isDynamic == MethodDescriptorFlagsBaseline.firstClassTestMethod.isDynamic)
        #expect(constructed.isInstance == MethodDescriptorFlagsBaseline.firstClassTestMethod.isInstance)
    }

    @Test func kind() async throws {
        let flags = try loadFirstFlags()
        let result = try acrossAllReaders(
            file: { flags.file.kind.rawValue },
            image: { flags.image.kind.rawValue }
        )
        #expect(result == MethodDescriptorFlagsBaseline.firstClassTestMethod.kindRawValue)
    }

    @Test func isDynamic() async throws {
        let flags = try loadFirstFlags()
        let result = try acrossAllReaders(
            file: { flags.file.isDynamic },
            image: { flags.image.isDynamic }
        )
        #expect(result == MethodDescriptorFlagsBaseline.firstClassTestMethod.isDynamic)
    }

    @Test func isInstance() async throws {
        let flags = try loadFirstFlags()
        let result = try acrossAllReaders(
            file: { flags.file.isInstance },
            image: { flags.image.isInstance }
        )
        #expect(result == MethodDescriptorFlagsBaseline.firstClassTestMethod.isInstance)
    }

    @Test func _hasAsyncBitSet() async throws {
        let flags = try loadFirstFlags()
        let result = try acrossAllReaders(
            file: { flags.file._hasAsyncBitSet },
            image: { flags.image._hasAsyncBitSet }
        )
        #expect(result == MethodDescriptorFlagsBaseline.firstClassTestMethod.hasAsyncBitSet)
    }

    @Test func isAsync() async throws {
        let flags = try loadFirstFlags()
        let result = try acrossAllReaders(
            file: { flags.file.isAsync },
            image: { flags.image.isAsync }
        )
        #expect(result == MethodDescriptorFlagsBaseline.firstClassTestMethod.isAsync)
    }

    @Test func isCoroutine() async throws {
        let flags = try loadFirstFlags()
        let result = try acrossAllReaders(
            file: { flags.file.isCoroutine },
            image: { flags.image.isCoroutine }
        )
        #expect(result == MethodDescriptorFlagsBaseline.firstClassTestMethod.isCoroutine)
    }

    @Test func isCalleeAllocatedCoroutine() async throws {
        let flags = try loadFirstFlags()
        let result = try acrossAllReaders(
            file: { flags.file.isCalleeAllocatedCoroutine },
            image: { flags.image.isCalleeAllocatedCoroutine }
        )
        #expect(result == MethodDescriptorFlagsBaseline.firstClassTestMethod.isCalleeAllocatedCoroutine)
    }

    @Test func isData() async throws {
        let flags = try loadFirstFlags()
        let result = try acrossAllReaders(
            file: { flags.file.isData },
            image: { flags.image.isData }
        )
        #expect(result == MethodDescriptorFlagsBaseline.firstClassTestMethod.isData)
    }

    @Test func extraDiscriminator() async throws {
        let flags = try loadFirstFlags()
        let result = try acrossAllReaders(
            file: { flags.file.extraDiscriminator },
            image: { flags.image.extraDiscriminator }
        )
        #expect(result == MethodDescriptorFlagsBaseline.firstClassTestMethod.extraDiscriminator)
    }
}
