import Testing
import Foundation
@testable import MachOSwiftSection
import MachOKit

@Suite
struct DyldCacheFileTests {
    enum Error: Swift.Error {
        case notFound
    }

    let mainCache: DyldCache

    let mainCacheMachOFileInCache: MachOFile
    
    let subCache: DyldCache

    let subCacheMachOFileInCache: MachOFile

    init() throws {
        // Cache
        let arch = "arm64e"
        let mainCachePath = "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_\(arch)"
        let subCachePath = "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_\(arch).01"
//        let mainCachePath = "/Volumes/Resources/24F74__MacOS/dyld_shared_cache_\(arch)"
//        let subCachePath = "/Volumes/Resources/24F74__MacOS/dyld_shared_cache_\(arch).01"
//        let mainCachePath = "/Volumes/RE/Dyld-Shared-Cache/macOS/15.5/dyld_shared_cache_\(arch)"
//        let subCachePath = "/Volumes/RE/Dyld-Shared-Cache/macOS/15.5/dyld_shared_cache_\(arch).01"
        let mainCacheURL = URL(fileURLWithPath: mainCachePath)
        let subCacheURL = URL(fileURLWithPath: subCachePath)
        self.mainCache = try! DyldCache(url: mainCacheURL)
        self.subCache = try! DyldCache(subcacheUrl: subCacheURL, mainCacheHeader: mainCache.mainCacheHeader)
        self.mainCacheMachOFileInCache = mainCache.machOFiles().first(where: {
            $0.imagePath.contains("/AppKit")
        })!
        self.subCacheMachOFileInCache = subCache.machOFiles().first(where: {
            $0.imagePath.contains("/SwiftUI")
        })!
    }

    @Test func protocolsInFile() async throws {
        guard let protocols = subCacheMachOFileInCache.swift.protocolDescriptors else {
            throw Error.notFound
        }
        for proto in protocols {
            try print(proto.name(in: subCacheMachOFileInCache))
        }
    }

    @MainActor
    @Test func types() async throws {
        let machOFile = mainCacheMachOFileInCache
        let typeContextDescriptors = try required(machOFile.swift.typeContextDescriptors)

        for typeContextDescriptor in typeContextDescriptors {
            switch typeContextDescriptor.flags.kind {
            case .enum:
                let enumDescriptor = try required(typeContextDescriptor.enumDescriptor(in: machOFile))
                let enumType = try Enum(descriptor: enumDescriptor, in: machOFile)
                print(enumType)
            case .struct:
                let structDescriptor = try required(typeContextDescriptor.structDescriptor(in: machOFile))
                let structType = try Struct(descriptor: structDescriptor, in: machOFile)
                print(structType)
            case .class:
                let classDescriptor = try required(typeContextDescriptor.classDescriptor(in: machOFile))
                let classType = try Class(descriptor: classDescriptor, in: machOFile)
                print(classType)
            default:
                break
            }
        }
    }
    
    @Test func dumpType() async throws {
        let machOFile = mainCacheMachOFileInCache
        try await Dump.dumpTypeContextDescriptors(in: machOFile)
    }
    
    @Test func cacheFileOffsets() async throws {
        for machOFile in mainCache.machOFiles() {
            print(machOFile.imagePath, machOFile.headerStartOffsetInCache)
        }
    }
}
