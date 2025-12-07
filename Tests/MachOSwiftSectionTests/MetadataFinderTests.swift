import Foundation
import Testing
import MachOKit
@_spi(Internals) import MachOSymbols
import MachOFoundation
import Demangling
@testable import MachOSwiftSection
@testable import MachOTestingSupport
@testable import SwiftDump
@testable import SwiftInspection
import Dependencies

@Suite
final class MetadataFinderTests: DyldCacheTests, @unchecked Sendable {
    override class var cacheImageName: MachOImageName { .AppKit }

    @Dependency(\.symbolIndexStore)
    private var symbolIndexStore

    @Test func dumpMetadatasInAppKit() async throws {
        let symbols = symbolIndexStore.symbols(of: .typeMetadata, in: machOFileInCache)
        for symbol in symbols {
            let metadata = try Metadata.resolve(from: symbol.offset, in: machOFileInCache)
            try print(demangleAsNode(symbol.name).print(using: .default), terminator: " ")
            print(metadata.kind)
        }
    }

    @Test func dumpMetadatasInSwiftUI() async throws {
        try await dumpMetadatas(for: #require(mainCache.machOFile(named: .SwiftUI)))
    }

    private func dumpMetadatas(for machO: MachOFile) async throws {
        let finder: MetadataFinder<MachOFile> = .init(machO: machO)

        let typeDescriptors = try machO.swift.typeContextDescriptors

        for typeDescriptor in typeDescriptors {
            switch typeDescriptor {
            case .enum /* (let enumDescriptor) */:
                continue
            case .struct(let structDescriptor):
                guard let metadata = try finder.metadata(for: structDescriptor) as StructMetadata? else {
                    continue
                }
                try await Struct(descriptor: structDescriptor, in: machO).dump(using: .demangleOptions(.test), in: machO).string.print()
                try metadata.fieldOffsets(for: structDescriptor, in: machO).print()
            case .class(let classDescriptor):
                guard let metadata = try finder.metadata(for: classDescriptor) as ClassMetadataObjCInterop? else {
                    continue
                }
                try await Class(descriptor: classDescriptor, in: machO).dump(using: .demangleOptions(.test), in: machO).string.print()
                try metadata.fieldOffsets(for: classDescriptor, in: machO).print()
            }
        }
    }
}
