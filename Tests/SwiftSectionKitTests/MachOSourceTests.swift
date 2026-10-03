import Foundation
import Testing
import SwiftSectionKit

/// `MachOSource.load()` is the one loader every request shares; these pin the
/// fat-binary affordance and the cache-image lookup it centralizes.
@Suite
struct MachOSourceTests {
    @Test("A thin file loads, whatever architecture is asked for")
    func thinFileIgnoresTheArchitecture() throws {
        let machOFile = try MachOSource.file(path: FixtureFiles.symbolTestsCore, architecture: .x86_64).load()
        #expect(machOFile.imagePath.hasSuffix("SymbolTestsCore"))
    }

    @Test("A fat file without an architecture names the slices it has")
    func fatFileRequiresAnArchitecture() throws {
        let directoryURL = try FixtureFiles.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fatPath = try FixtureFiles.makeSingleSliceFatFile(wrapping: FixtureFiles.symbolTestsCore, in: directoryURL)

        #expect(throws: MachOSourceError.fatBinaryRequiresArchitecture(availableArchitectures: ["arm64"])) {
            try MachOSource.file(path: fatPath, architecture: nil).load()
        }
    }

    @Test("A fat file yields the slice asked for, and rejects one it lacks")
    func fatFileSliceSelection() throws {
        let directoryURL = try FixtureFiles.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let fatPath = try FixtureFiles.makeSingleSliceFatFile(wrapping: FixtureFiles.symbolTestsCore, in: directoryURL)

        let machOFile = try MachOSource.file(path: fatPath, architecture: .arm64).load()
        #expect(machOFile.imagePath.hasSuffix("SymbolTestsCore"))
        #expect(throws: MachOSourceError.architectureNotFound(.arm64e)) {
            try MachOSource.file(path: fatPath, architecture: .arm64e).load()
        }
    }

    @Test("An image the system cache does not have is reported by the name asked for")
    func missingCacheImage() throws {
        #expect(throws: MachOSourceError.dyldSharedCacheImageNotFound(.name("NoSuchImageInAnyCache"))) {
            try MachOSource.systemDyldSharedCache(image: .name("NoSuchImageInAnyCache")).load()
        }
    }

    @Test("The library's loading errors name no command-line option", arguments: [
        MachOSourceError.fatBinaryRequiresArchitecture(availableArchitectures: ["arm64", "x86_64"]),
        .architectureNotFound(.arm64e),
        .dyldSharedCacheImageNotFound(.name("Foundation")),
        .dyldSharedCacheImageNotFound(.path("/usr/lib/libobjc.A.dylib")),
        .systemDyldSharedCacheUnavailable,
    ])
    func errorDescriptionIsOptionFree(error: MachOSourceError) throws {
        let description = try #require(error.errorDescription)
        #expect(!description.isEmpty)
        #expect(!description.contains("--"))
    }
}
