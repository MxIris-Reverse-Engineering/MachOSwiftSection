import Foundation
import Testing
import MachOKit
import MachOMacro
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
import MachOTestingSupport

@Suite(.serialized)
struct DyldCacheDumpTests: DumpableTest {
    let mainCache: DyldCache

    let subCache: DyldCache

    let machOFileInMainCache: MachOFile

    let machOFileInSubCache: MachOFile

    let machOFileInCache: MachOFile

    let isEnabledSearchMetadata: Bool = false

    init() async throws {
        self.mainCache = try DyldCache(path: .current)
        self.subCache = try required(mainCache.subCaches?.first?.subcache(for: mainCache))

        self.machOFileInMainCache = try #require(mainCache.machOFile(named: .SwiftUI))
        self.machOFileInSubCache = if #available(macOS 15.5, *) {
            try #require(subCache.machOFile(named: .CodableSwiftUI))
        } else {
            try #require(subCache.machOFile(named: .UIKitCore))
        }

        self.machOFileInCache = try #require(mainCache.machOFile(named: .AttributeGraph))
    }
}

@Suite(.serialized)
struct MachOFileDumpTests: DumpableTest {
    let machOFile: MachOFile

    let isEnabledSearchMetadata: Bool = false

    init() async throws {
        let file = try loadFromFile(named: .iOS_23A5260l_Simulator_SwiftUICore)
        switch file {
        case .fat(let fatFile):
            self.machOFile = try #require(fatFile.machOFiles().first(where: { $0.header.cpu.subtype == .arm64(.arm64_all) }))
        case .machO(let machO):
            self.machOFile = machO
        @unknown default:
            fatalError()
        }
    }
}

@Suite(.serialized)
struct MachOImageDumpTests: DumpableTest {
    let machOImage: MachOImage

    let isEnabledSearchMetadata: Bool = false

    init() async throws {
        self.machOImage = try #require(MachOImage(named: .Foundation))
    }
}

extension DyldCacheDumpTests {
    @Test func typesInCacheFile() async throws {
        try await dumpTypes(for: machOFileInCache)
    }

    @Test func typesInMainCacheFile() async throws {
        try await dumpTypes(for: machOFileInMainCache)
    }

    @Test func typesInSubCacheFile() async throws {
        try await dumpTypes(for: machOFileInSubCache)
    }

    @Test func protocolsInCacheFile() async throws {
        try await dumpProtocols(for: machOFileInCache)
    }

    @Test func protocolsInMainCacheFile() async throws {
        try await dumpProtocols(for: machOFileInMainCache)
    }

    @Test func protocolsInSubCacheFile() async throws {
        try await dumpProtocols(for: machOFileInSubCache)
    }

    @Test func protocolConformancesInCacheFile() async throws {
        try await dumpProtocolConformances(for: machOFileInCache)
    }

    @Test func protocolConformancesInMainCacheFile() async throws {
        try await dumpProtocolConformances(for: machOFileInMainCache)
    }

    @Test func protocolConformancesInSubCacheFile() async throws {
        try await dumpProtocolConformances(for: machOFileInSubCache)
    }

    @Test func associatedTypesInCacheFile() async throws {
        try await dumpAssociatedTypes(for: machOFileInCache)
    }

    @Test func associatedTypesInCacheMainFile() async throws {
        try await dumpAssociatedTypes(for: machOFileInMainCache)
    }

    @Test func associatedTypesInSubCacheFile() async throws {
        try await dumpAssociatedTypes(for: machOFileInSubCache)
    }
}

extension MachOFileDumpTests {
    @Test func typesInFile() async throws {
        try await dumpTypes(for: machOFile)
    }

    @Test func protocolsInFile() async throws {
        try await dumpProtocols(for: machOFile)
    }

    @Test func protocolConformancesInFile() async throws {
        try await dumpProtocolConformances(for: machOFile)
    }

    @Test func associatedTypesInFile() async throws {
        try await dumpAssociatedTypes(for: machOFile)
    }
}

extension MachOImageDumpTests {
    @Test func typesInImage() async throws {
        try await dumpTypes(for: machOImage)
    }

    @Test func protocolsInImage() async throws {
        try await dumpProtocols(for: machOImage)
    }

    @Test func protocolConformancesInImage() async throws {
        try await dumpProtocolConformances(for: machOImage)
    }

    @Test func associatedTypesInImage() async throws {
        try await dumpAssociatedTypes(for: machOImage)
    }
}

protocol DumpableTest {
    var isEnabledSearchMetadata: Bool { get }
}

extension DumpableTest {
    @MachOImageGenerator
    @MainActor
    func dumpProtocols(for machO: MachOFile) async throws {
        let protocolDescriptors = try machO.swift.protocolDescriptors
        for protocolDescriptor in protocolDescriptors {
            try print(Protocol(descriptor: protocolDescriptor, in: machO).dump(using: printOptions, in: machO).string)
        }
    }

    @MachOImageGenerator
    @MainActor
    func dumpProtocolConformances(for machO: MachOFile) async throws {
        let protocolConformanceDescriptors = try machO.swift.protocolConformanceDescriptors

        for protocolConformanceDescriptor in protocolConformanceDescriptors {
            try print(ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machO).dump(using: printOptions, in: machO).string)
        }
    }

    @MachOImageGenerator
    @MainActor
    func dumpTypes(for machO: MachOFile) async throws {
        let typeContextDescriptors = try machO.swift.typeContextDescriptors
        var metadataFinder: MetadataFinder<MachOFile>?
        if isEnabledSearchMetadata {
            metadataFinder = MetadataFinder(machO: machO)
        }
        for typeContextDescriptor in typeContextDescriptors {
            switch typeContextDescriptor {
            case .type(let typeContextDescriptorWrapper):
                switch typeContextDescriptorWrapper {
                case .enum(let enumDescriptor):
                    let enumType = try Enum(descriptor: enumDescriptor, in: machO)
                    try print(enumType.dump(using: printOptions, in: machO).string)
                case .struct(let structDescriptor):
                    let structType = try Struct(descriptor: structDescriptor, in: machO)
                    try print(structType.dump(using: printOptions, in: machO).string)
                    if let metadata = try metadataFinder?.metadata(for: structDescriptor) as StructMetadata? {
                        try print(metadata.fieldOffsets(for: structDescriptor, in: machO))
                    }
                case .class(let classDescriptor):
                    let classType = try Class(descriptor: classDescriptor, in: machO)
                    try print(classType.dump(using: printOptions, in: machO).string)
                    if let metadata = try metadataFinder?.metadata(for: classDescriptor) as ClassMetadataObjCInterop? {
                        try print(metadata.fieldOffsets(for: classDescriptor, in: machO))
                    }
                }
            default:
                break
            }
        }
    }

    @MachOImageGenerator
    @MainActor
    func dumpAssociatedTypes(for machO: MachOFile) async throws {
        let associatedTypeDescriptors = try machO.swift.associatedTypeDescriptors
        for associatedTypeDescriptor in associatedTypeDescriptors {
            try print(AssociatedType(descriptor: associatedTypeDescriptor, in: machO).dump(using: printOptions, in: machO).string)
        }
    }
}

extension String {
    func print() {
        Swift.print(self)
    }
}
