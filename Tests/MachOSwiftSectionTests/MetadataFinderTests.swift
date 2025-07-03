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

    init() throws {
        self.mainCache = try DyldCache(path: .current)
    }

    @Test func dumpMetadatasInAppKit() async throws {
        try await dumpMetadatas(for: #require(mainCache.machOFile(named: .AppKit)))
    }

    @Test func dumpMetadatasInSwiftUI() async throws {
        try await dumpMetadatas(for: #require(mainCache.machOFile(named: .SwiftUI)))
    }
    
    private func dumpMetadatas(for machO: MachOFile) async throws {
        let finder: MetadataFinder<MachOFile> = .init(machO: machO)

        let typeDescriptors = try machO.swift.typeContextDescriptors

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
