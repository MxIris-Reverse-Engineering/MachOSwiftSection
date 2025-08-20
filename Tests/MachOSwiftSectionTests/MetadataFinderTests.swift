import Foundation
import Testing
import MachOKit
import MachOMacro
import MachOFoundation
import Demangle
@testable import MachOSwiftSection
@testable import MachOTestingSupport

@Suite
final class MetadataFinderTests: DyldCacheTests {

    override class var cacheImageName: MachOImageName { .AppKit }
    
    @Test func dumpMetadatasInAppKit() async throws {
        let symbols = SymbolIndexStore.shared.symbols(of: .typeMetadata, in: machOFileInCache)
        for symbol in symbols {
            let metadata = try Metadata.resolve(from: symbol.offset, in: machOFileInCache)
            print(try demangleAsNode(symbol.stringValue).print(using: .default), terminator: " ")
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
            case .enum/*(let enumDescriptor)*/:
                continue
            case .struct(let structDescriptor):
                guard let metadata = try finder.metadata(for: structDescriptor) as StructMetadata? else {
                    continue
                }
//                try Struct(descriptor: structDescriptor, in: machO).dump(using: .test, in: machO).string.print()
                try metadata.fieldOffsets(for: structDescriptor, in: machO).print()
            case .class(let classDescriptor):
                guard let metadata = try finder.metadata(for: classDescriptor) as ClassMetadataObjCInterop? else {
                    continue
                }
//                try Class(descriptor: classDescriptor, in: machO).dump(using: .test, in: machO).string.print()
                try metadata.fieldOffsets(for: classDescriptor, in: machO).print()
            }
        }
    }
}
