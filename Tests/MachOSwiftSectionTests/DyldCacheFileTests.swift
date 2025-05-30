import Testing
import Foundation
import MachOKit
@testable import MachOSwiftSection

@Suite
struct DyldCacheFileTests {
    let mainCache: DyldCache

    let mainCacheMachOFileInCache: MachOFile

    let subCache: DyldCache

    let subCacheMachOFileInCache: MachOFile

    let machOFileInCache: MachOFile

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
//            $0.imagePath.contains("/AppKit")
            $0.imagePath.contains("/SwiftUI")
        })!

        self.subCacheMachOFileInCache = subCache.machOFiles().first(where: {
            $0.imagePath.contains("SwiftUI")
        })!

        self.machOFileInCache = (mainCache.machOFiles().map { $0 } + subCache.machOFiles().map { $0 }).first {
            $0.imagePath.contains("SwiftData")
        }!
    }

    @Test func protocolNames() async throws {
        let protocols = try required(subCacheMachOFileInCache.swift.protocolDescriptors)
        for proto in protocols {
            try print(proto.name(in: subCacheMachOFileInCache))
        }
    }

    @Test func symbolTable() async throws {
        for string in machOFileInCache.symbolStrings! {
            print(string.offset, string.string)
        }
    }

    @MainActor
    @Test func types() async throws {
        try await dumpTypes(for: machOFileInCache)
    }

    @MainActor
    @Test func mainCacheTypes() async throws {
        try await dumpTypes(for: mainCacheMachOFileInCache)
    }

    @MainActor
    @Test func subCacheTypes() async throws {
        try await dumpTypes(for: subCacheMachOFileInCache)
    }

    private func dumpTypes(for machOFile: MachOFile) async throws {
        let typeContextDescriptors = try required(machOFile.swift.typeContextDescriptors)

        for typeContextDescriptor in typeContextDescriptors {
            switch typeContextDescriptor.flags.kind {
            case .enum:
                let enumDescriptor = try required(typeContextDescriptor.enumDescriptor(in: machOFile))
                let enumType = try Enum(descriptor: enumDescriptor, in: machOFile)
                try print(enumType.dump(using: printOptions, in: machOFile))
            case .struct:
                let structDescriptor = try required(typeContextDescriptor.structDescriptor(in: machOFile))
                let structType = try Struct(descriptor: structDescriptor, in: machOFile)
                try print(structType.dump(using: printOptions, in: machOFile))
            case .class:
                let classDescriptor = try required(typeContextDescriptor.classDescriptor(in: machOFile))
                let classType = try Class(descriptor: classDescriptor, in: machOFile)
                try print(classType.dump(using: printOptions, in: machOFile))
            default:
                break
            }
        }
    }

    @Test func cacheFiles() async throws {
        print("Main Cache MachO Files:")
        for machOFile in mainCache.machOFiles() {
            print(machOFile.imagePath)
        }
        print("Sub Cache MachO Files:")
        for machOFile in subCache.machOFiles() {
            print(machOFile.imagePath)
        }
    }
}
