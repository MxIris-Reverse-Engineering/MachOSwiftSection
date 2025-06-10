import Foundation
import Testing
import MachOKit
import MachOTestingSupport
import MachOMacro
@testable import MachOSwiftSection

@Suite
struct MetadataFinderTests {
    let mainCache: DyldCache

    let subCache: DyldCache

    let machOFileInMainCache: MachOFile

    let machOFileInSubCache: MachOFile

    let machOFileInCache: MachOFile

    let machOFile: MachOFile

    let machOImage: MachOImage

    init() throws {
        // Cache
        let arch = "arm64e"
        let mainCachePath = "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_\(arch)"
        let subCachePath = "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_\(arch).01"
        let mainCacheURL = URL(fileURLWithPath: mainCachePath)
        let subCacheURL = URL(fileURLWithPath: subCachePath)
        self.mainCache = try DyldCache(url: mainCacheURL)
        self.subCache = try DyldCache(subcacheUrl: subCacheURL, mainCacheHeader: mainCache.mainCacheHeader)

        self.machOFileInMainCache = try #require(mainCache.machOFile(named: .SwiftUICore))

        self.machOFileInSubCache = if #available(macOS 15.5, *) {
            try #require(subCache.machOFile(named: .CodableSwiftUI))
        } else {
            try #require(subCache.machOFile(named: .UIKitCore))
        }

        self.machOFileInCache = try #require(mainCache.machOFile(named: .AttributeGraph))

        // File
        let file = try loadFromFile(named: .ControlCenter)
        switch file {
        case .fat(let fatFile):
            self.machOFile = try #require(fatFile.machOFiles().first(where: { $0.header.cpu.type == .x86_64 }))
        case .machO(let machO):
            self.machOFile = machO
        @unknown default:
            fatalError()
        }

        // Image
        self.machOImage = try #require(MachOImage(named: .Foundation))
    }

    @Test func dumpMetadatasInMainCache() async throws {
        try await dumpMetadatas(for: machOFileInMainCache)
    }

    @MachOImageGenerator
    private func dumpMetadatas(for machO: MachOFile) async throws {
        let finder: MetadataFinder<MachOFile> = .init(machO: machO)

        let typeDescriptors = try machOFileInMainCache.swift.typeContextDescriptors

        for typeDescriptor in typeDescriptors {
            guard case .type(let type) = typeDescriptor else {
                continue
            }
            switch type {
            case .enum:
//                guard let metadata = try finder.metadata(for: enumDescriptor) as Enumme? else {
//                    continue
//                }
                continue
            case .struct(let structDescriptor):
                guard let metadata = try finder.metadata(for: structDescriptor) as StructMetadata? else {
                    continue
                }

                try print(metadata.fieldOffsets(for: structDescriptor, in: machO))
            case .class(let classDescriptor):
                guard let metadata = try finder.metadata(for: classDescriptor) as ClassMetadataObjCInterop? else {
                    continue
                }

                try print(metadata.fieldOffsets(for: classDescriptor, in: machO))
            }
        }
    }
}
