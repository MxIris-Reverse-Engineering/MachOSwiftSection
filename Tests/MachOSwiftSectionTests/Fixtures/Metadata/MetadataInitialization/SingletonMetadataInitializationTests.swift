import Foundation
import Testing
import MachOFoundation
@testable import MachOSwiftSection
@testable import MachOTestingSupport

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
        // Cross-reader equality on each of the three RelativeOffsets.
        let cacheOffset = try acrossAllReaders(
            file: { inits.file.layout.initializationCacheOffset },
            image: { inits.image.layout.initializationCacheOffset }
        )
        let incompleteOffset = try acrossAllReaders(
            file: { inits.file.layout.incompleteMetadata },
            image: { inits.image.layout.incompleteMetadata }
        )
        let completionOffset = try acrossAllReaders(
            file: { inits.file.layout.completionFunction },
            image: { inits.image.layout.completionFunction }
        )

        // Recover the signed Int32 values from the UInt64 baseline bits.
        let expectedCache = Int32(truncatingIfNeeded: SingletonMetadataInitializationBaseline.firstSingletonInit.initializationCacheRelativeOffsetBits)
        let expectedIncomplete = Int32(truncatingIfNeeded: SingletonMetadataInitializationBaseline.firstSingletonInit.incompleteMetadataRelativeOffsetBits)
        let expectedCompletion = Int32(truncatingIfNeeded: SingletonMetadataInitializationBaseline.firstSingletonInit.completionFunctionRelativeOffsetBits)
        #expect(cacheOffset == expectedCache)
        #expect(incompleteOffset == expectedIncomplete)
        #expect(completionOffset == expectedCompletion)
    }
}
