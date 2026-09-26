import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport
import MachOFixtureSupport

/// Fixture-based Suite for `SingletonMetadataInitialization`.
///
/// `SingletonMetadataInitialization` is appended to descriptors with the
/// `hasSingletonMetadataInitialization` bit (resilient classes / certain
/// generic-class shapes). The picker selects the first such ClassDescriptor
/// in `SymbolTestsCore` and the Suite asserts cross-reader equality on
/// the relative-offset triple recorded in the baseline.
///
/// `init(layout:offset:)` is filtered as memberwise-synthesized.
@Suite
final class SingletonMetadataInitializationTests: MachOSwiftSectionFixtureTests, FixtureSuite, @unchecked Sendable {
    static let testedTypeName = "SingletonMetadataInitialization"
    static var registeredTestMethodNames: Set<String> {
        SingletonMetadataInitializationBaseline.registeredTestMethodNames
    }

    /// Helper: load the picked class descriptor and its
    /// SingletonMetadataInitialization payload from both readers.
    private func loadInits() throws -> (file: SingletonMetadataInitialization, image: SingletonMetadataInitialization) {
        let fileDescriptor = try BaselineFixturePicker.class_singletonMetadataInitFirst(in: machOFile)
        let imageDescriptor = try BaselineFixturePicker.class_singletonMetadataInitFirst(in: machOImage)
        let fileClass = try Class(descriptor: fileDescriptor, in: machOFile)
        let imageClass = try Class(descriptor: imageDescriptor, in: machOImage)
        return (
            file: try required(fileClass.singletonMetadataInitialization),
            image: try required(imageClass.singletonMetadataInitialization)
        )
    }

    @Test func offset() async throws {
        let inits = try loadInits()
        // Both readers must agree on the absolute offset within the
        // descriptor's trailing-objects layout.
        let result = try acrossAllReaders(
            file: { inits.file.offset },
            image: { inits.image.offset }
        )
        #expect(result > 0)
    }

    @Test func layout() async throws {
        let inits = try loadInits()
        // Cross-reader equality on each of the three relative pointers.
        let cacheOffset = try acrossAllReaders(
            file: { inits.file.layout.initializationCacheOffset.relativeOffset },
            image: { inits.image.layout.initializationCacheOffset.relativeOffset }
        )
        let incompleteOffset = try acrossAllReaders(
            file: { inits.file.layout.incompleteMetadata.relativeOffset },
            image: { inits.image.layout.incompleteMetadata.relativeOffset }
        )
        let completionOffset = try acrossAllReaders(
            file: { inits.file.layout.completionFunction.relativeOffset },
            image: { inits.image.layout.completionFunction.relativeOffset }
        )

        // Recover the signed Int32 values from the UInt64 baseline bits.
        let expectedCache = Int32(truncatingIfNeeded: SingletonMetadataInitializationBaseline.firstSingletonInit.initializationCacheRelativeOffsetBits)
        let expectedIncomplete = Int32(truncatingIfNeeded: SingletonMetadataInitializationBaseline.firstSingletonInit.incompleteMetadataRelativeOffsetBits)
        let expectedCompletion = Int32(truncatingIfNeeded: SingletonMetadataInitializationBaseline.firstSingletonInit.completionFunctionRelativeOffsetBits)
        #expect(cacheOffset == expectedCache)
        #expect(incompleteOffset == expectedIncomplete)
        #expect(completionOffset == expectedCompletion)

        // Resolved through the shared helper. The middle field is a UNION —
        // for this carrier, a class WITHOUT a resilient superclass, it holds
        // the incomplete metadata; `ResilientClassMetadataPatternTests` reads
        // the same word on a carrier where it is a pattern instead.
        let resolvedIncomplete = try acrossAllReaders(
            file: { inits.file.resolvedDirectOffset(from: \.incompleteMetadata) },
            image: { inits.image.resolvedDirectOffset(from: \.incompleteMetadata) }
        )
        #expect(resolvedIncomplete == SingletonMetadataInitializationBaseline.firstSingletonInit.incompleteMetadataOffset)

        let resolvedCompletion = try acrossAllReaders(
            file: { inits.file.resolvedDirectOffset(from: \.completionFunction) },
            image: { inits.image.resolvedDirectOffset(from: \.completionFunction) }
        )
        #expect(resolvedCompletion == SingletonMetadataInitializationBaseline.firstSingletonInit.completionFunctionOffset)
    }

}
