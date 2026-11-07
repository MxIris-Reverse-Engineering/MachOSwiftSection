import Foundation
import Testing
@_spi(Support) import MachOKit
import MachOKitExtensions
@testable import MachOReading
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

    /// Images of one cache file, their cache instances and the sub-cache
    /// instance another image's read crosses into the file through all read
    /// one mapping.
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

        let mappingStart = try #require(firstImage.fileBytes.baseAddress)
        #expect(secondImage.fileBytes.baseAddress == mappingStart)
        #expect(firstImageCache.fileBytes.baseAddress == mappingStart)
        #expect(secondImageCache.fileBytes.baseAddress == mappingStart)
        #expect(crossedCache.fileBytes.baseAddress == mappingStart)
    }

    /// A read never goes back to the file's path: removed after it was
    /// opened, the file still reads through the mapping made when it was
    /// opened.
    @Test func aRemovedFileStillReadsThroughTheMappingMadeWhenItWasOpened() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileMappingTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let copyURL = temporaryDirectory.appendingPathComponent("dyld")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/lib/dyld"), to: copyURL)
        let machOFile = try #require(try Self.firstMachOFile(at: copyURL))
        try FileManager.default.removeItem(at: copyURL)

        let magic: UInt32 = try machOFile.readElement(offset: 0)
        #expect(magic == machOFile.header.magic?.rawValue)
    }

    /// A read outside the file throws rather than reading past the mapping.
    @Test func aReadPastTheEndOfTheFileThrows() throws {
        let machOFile = try #require(try Self.firstMachOFile(at: URL(fileURLWithPath: "/usr/lib/dyld")))
        let pastTheEnd = machOFile.fileBytes.count - machOFile.headerStartOffset
        #expect(throws: (any Error).self) {
            let _: UInt64 = try machOFile.readElement(offset: pastTheEnd - 4)
        }
        #expect(throws: (any Error).self) {
            let _: [UInt32] = try machOFile.readElements(offset: pastTheEnd - 8, numberOfElements: 4)
        }
        #expect(throws: (any Error).self) {
            _ = try machOFile.readString(offset: pastTheEnd + 1)
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

    private static func firstMachOFile(at url: URL) throws -> MachOFile? {
        switch try MachOKit.loadFromFile(url: url) {
        case .machO(let machOFile):
            return machOFile
        case .fat(let fatFile):
            return try fatFile.machOFiles().first
        }
    }
}
