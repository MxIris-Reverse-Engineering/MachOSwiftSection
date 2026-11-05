import Foundation
import Testing
import MachOKit
import MachOKitExtensions
@testable import MachOReading
import MachOSwiftSection
import MachOFixtureSupport

/// Every reader of one file reads it through one mapping, and one that cannot
/// be made fails the read.
///
/// MachOKit hands out a new `DyldCache` for every image a `FullDyldCache`
/// enumerates, MachOKitExtensions another for every sub-cache an image's reads
/// cross into, and a dependency locator makes a `MachOFile` of its own for
/// every image it locates. Mapped once per instance, a cache file was mapped
/// again for each of them, and each mapping holds a descriptor: RuntimeViewer's
/// offline service, reading Dock.app against the system's cache, held 2,548
/// descriptors on 85 cache files when the next open failed with `EMFILE` and
/// the accessor's `try!` stopped the process.
@Suite
struct SharedFileMappingTests {
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
                try SharedFileMappingTests.readSwiftImagesOfTheHostCacheUnderTheServiceDescriptorLimit()
            } catch {
                // A thrown error ends the child on a trap too; exiting keeps a
                // read that failed apart from an accessor that stopped.
                exit(EXIT_FAILURE)
            }
        }
    }

    @Test(.enabled(if: isHostDyldCacheAvailable))
    func readersOfOneCacheFileShareOneMapping() throws {
        let cache = try FullDyldCache(url: URL(fileURLWithPath: DyldSharedCachePath.current.rawValue))
        let images = Array(cache.machOFiles())
        let imagesByFile = Dictionary(grouping: images, by: \.url.path)
        let (filePath, imagesOfOneFile) = try #require(imagesByFile.first { $0.key != cache.url.path && $0.value.count >= 2 })
        let firstImage = imagesOfOneFile[0]
        let secondImage = imagesOfOneFile[1]
        let firstImageCache = try #require(firstImage.cache)
        let secondImageCache = try #require(secondImage.cache)
        // What makes the sharing necessary: MachOKit gives each image a cache
        // instance of its own.
        try #require(firstImageCache !== secondImageCache)

        // Another image's read of the first image's header crosses into the
        // first image's file through a sub-cache instance of its own.
        let otherImage = try #require(images.first { $0.url.path != filePath && $0.url.path != cache.url.path })
        let headerAddress = try #require(cache.imageInfos?.first { $0.path(in: cache) == firstImage.imagePath }?.address)
        let (crossedCache, _) = try #require(otherImage.cacheAndFileOffset(for: headerAddress))

        let mapping = try firstImage.fileIO
        #expect(try secondImage.fileIO === mapping)
        #expect(try firstImageCache.fileIO === mapping)
        #expect(try secondImageCache.fileIO === mapping)
        #expect(try crossedCache.fileIO === mapping)
    }

    @Test func aFileThatCannotBeMappedFailsTheReadInsteadOfStoppingTheProcess() async {
        await #expect(processExitsWith: .success) {
            exit(SharedFileMappingTests.readOfARemovedFileThrows() ? EXIT_SUCCESS : EXIT_FAILURE)
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

    /// Whether a read of a file removed after it was opened, before anything
    /// mapped it for reading, throws. MachOKit keeps its own mapping of the
    /// file; the reading layer's is made on the first read, from the path.
    static func readOfARemovedFileThrows() -> Bool {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedFileMappingTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let copyURL = temporaryDirectory.appendingPathComponent("dyld")
        guard (try? FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)) != nil,
              (try? FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/lib/dyld"), to: copyURL)) != nil,
              let machOFile = try? firstMachOFile(at: copyURL),
              (try? FileManager.default.removeItem(at: copyURL)) != nil
        else {
            return false
        }
        do {
            let _: UInt32 = try machOFile.readElement(offset: 0)
            return false
        } catch {
            return true
        }
    }

    private static func firstMachOFile(at url: URL) throws -> MachOFile? {
        switch try MachOKit.loadFromFile(url: url) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            return try fatFile.machOFiles().first
        }
    }
}
