import Testing
import Foundation
@_spi(Core) @testable import MachOSwiftSection
import MachOKit

@Suite
struct AppKitSwiftSectionTests {
    enum Error: Swift.Error {
        case notFound
    }

    let cache: DyldCache

    let machOFileInCache: MachOFile

    init() throws {
        // Cache
        let arch = "arm64e"
        let cachePath = "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_\(arch)"
        let cacheUrl = URL(fileURLWithPath: cachePath)
        self.cache = try! DyldCache(url: cacheUrl)
        self.machOFileInCache = cache.machOFiles().first(where: {
            $0.imagePath.contains("/AppKit")
        })!
    }

    @Test func protocolsInFile() async throws {
        guard let protocols = machOFileInCache.swift.protocolDescriptors else {
            throw Error.notFound
        }
        for proto in protocols {
            print(try proto.name(in: machOFileInCache))
        }
    }
    
    @Test func typeContextDescriptorsInFile() async throws {
        do {
            try await Dump.dumpTypeContextDescriptors(in: machOFileInCache)
        } catch {
            print(error)
        }
    }
}
