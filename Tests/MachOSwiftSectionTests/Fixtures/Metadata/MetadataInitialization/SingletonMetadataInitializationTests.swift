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

    /// The middle field is a union. For this carrier — a class WITHOUT a
    /// resilient superclass — it holds the incomplete metadata, and
    /// ``resilientClassPatternOffset`` reads the same word under the other
    /// name. `ResilientClassMetadataPatternTests` covers the other reading on
    /// a carrier where it is the right one.
    @Test func incompleteMetadataOffset() async throws {
        let initializations = try loadInits()
        let result = try acrossAllReaders(
            file: { initializations.file.incompleteMetadataOffset },
            image: { initializations.image.incompleteMetadataOffset }
        )
        #expect(result == SingletonMetadataInitializationBaseline.firstSingletonInit.incompleteMetadataOffset)
    }

    @Test func resilientClassPatternOffset() async throws {
        let initializations = try loadInits()
        let result = try acrossAllReaders(
            file: { initializations.file.resilientClassPatternOffset },
            image: { initializations.image.resilientClassPatternOffset }
        )
        // Same word, deliberately: the ABI overlays the two and only the
        // owning descriptor's flag says which reading applies.
        #expect(result == initializations.file.incompleteMetadataOffset)
        #expect(result == SingletonMetadataInitializationBaseline.firstSingletonInit.incompleteMetadataOffset)
    }

    @Test func completionFunctionOffset() async throws {
        let initializations = try loadInits()
        let result = try acrossAllReaders(
            file: { initializations.file.completionFunctionOffset },
            image: { initializations.image.completionFunctionOffset }
        )
        #expect(result == SingletonMetadataInitializationBaseline.firstSingletonInit.completionFunctionOffset)
    }
}
