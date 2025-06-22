import Foundation
import Testing
import MachOKit
import MachOTestingSupport
import MachOMacro
import MachOFoundation
import SwiftDump
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
        self.mainCache = try DyldCache(path: .current)
        self.subCache = try required(mainCache.subCaches?.first?.subcache(for: mainCache))

        self.machOFileInMainCache = try #require(mainCache.machOFile(named: .SwiftUI))
        self.machOFileInSubCache = if #available(macOS 15.5, *) {
            try #require(subCache.machOFile(named: .CodableSwiftUI))
        } else {
            try #require(subCache.machOFile(named: .UIKitCore))
        }

        self.machOFileInCache = try #require(mainCache.machOFile(named: .AttributeGraph))

        // File
        let file = try loadFromFile(named: .Finder)
        switch file {
        case .fat(let fatFile):
            self.machOFile = try #require(fatFile.machOFiles().first(where: { $0.header.cpu.type == .arm64 }))
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
                continue
            case .struct(let structDescriptor):
                guard let metadata = try finder.metadata(for: structDescriptor) as StructMetadata? else {
                    continue
                }
                try Struct(descriptor: structDescriptor, in: machO).dump(using: .test, in: machO).string.print()
                try metadata.fieldOffsets(for: structDescriptor, in: machO).print()
            case .class(let classDescriptor):
                guard let metadata = try finder.metadata(for: classDescriptor) as ClassMetadataObjCInterop? else {
                    continue
                }
                try Class(descriptor: classDescriptor, in: machO).dump(using: .test, in: machO).string.print()
                try metadata.fieldOffsets(for: classDescriptor, in: machO).print()
            }
        }
    }
}
