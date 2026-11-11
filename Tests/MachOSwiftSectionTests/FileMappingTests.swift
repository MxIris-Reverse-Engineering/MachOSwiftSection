import Foundation
import Testing
import MachOKit
import MachOSwiftSection
import MachOFixtureSupport

/// A `MachOFile` is read through the mapping MachOKit made when it opened the
/// file (`fileBytes`), which every value assembled from that opening shares
/// (evolution proposal `machofile-performance`).
///
/// MachOKit hands out a new `DyldCache` for every image a `FullDyldCache`
/// enumerates, MachOKitExtensions another for every sub-cache an image's reads
/// cross into, and a dependency locator makes a `MachOFile` of its own for
/// every image it locates. Mapped once per instance, a cache file was mapped
/// again for each of them, and each mapping holds a descriptor: RuntimeViewer's
/// offline service, reading Dock.app against the system's cache, held 2,548
/// descriptors on 85 cache files when the next open failed with `EMFILE` and
/// the accessor's `try!` stopped the process. The reading layer then kept one
/// mapping of its own per opening, made on a file's first read; it now reads
/// MachOKit's, so it maps nothing and holds no descriptor of its own.
///
/// The reading layer itself moved to MachOKitExtensions, and with it the
/// tests of the mapping alone (one mapping shared by the readers of a cache
/// file, a removed file still read, a read past the end throwing). What stays
/// here reads Swift metadata through this package.
@Suite
struct FileMappingTests {
    private static var isHostDyldCacheAvailable: Bool {
        FileManager.default.fileExists(atPath: DyldSharedCachePath.current.rawValue)
    }

    /// More Swift images than an XPC service may hold descriptors: mapped per
    /// image the read runs out of them, mapped per file it cannot (the host's
    /// cache has fewer than a hundred files).
    private static let imageCount = 400

    /// The descriptor limit launchd starts an XPC service with.
    private static let serviceDescriptorLimit: rlim_t = 256

    @Test(.enabled(if: isHostDyldCacheAvailable))
    func readingManyImagesOfACacheStaysWithinAServiceDescriptorLimit() async {
        await #expect(processExitsWith: .success) {
            do {
                try FileMappingTests.readSwiftImagesOfTheHostCacheUnderTheServiceDescriptorLimit()
            } catch {
                // A thrown error ends the child on a trap too; exiting keeps a
                // read that failed apart from an accessor that stopped.
                exit(EXIT_FAILURE)
            }
        }
    }

    // MARK: - Exit test bodies

    /// Reads the type descriptors of `imageCount` Swift images of the host's
    /// cache, all kept alive as a host's catalog keeps them, under the service
    /// limit. The hard limit comes down too: the first use of `CFSocket`
    /// raises the soft one by 2,304 within the hard one, which would hide the
    /// exhaustion — it is how the offline service came to have 2,560.
    static func readSwiftImagesOfTheHostCacheUnderTheServiceDescriptorLimit() throws {
        var limit = rlimit(rlim_cur: serviceDescriptorLimit, rlim_max: serviceDescriptorLimit)
        guard setrlimit(RLIMIT_NOFILE, &limit) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL)
        }
        let cache = try FullDyldCache(url: URL(fileURLWithPath: DyldSharedCachePath.current.rawValue))
        let swiftImages = Array(
            cache.machOFiles()
                .lazy
                .filter { image in image.sections.contains { $0.sectionName == "__swift5_types" } }
                .prefix(imageCount)
        )
        guard swiftImages.count == imageCount else {
            throw POSIXError(.ENOENT)
        }
        for image in swiftImages {
            _ = try image.swift.typeContextDescriptors
        }
    }
}
