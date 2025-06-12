import Foundation
import Testing
import MachOKit
import MachOMacro
import MachOFoundation
@testable import MachOSwiftSection
@testable import SwiftDump
import MachOTestingSupport

@Suite(.serialized)
struct SwiftDumpTests {
    let mainCache: DyldCache

    let subCache: DyldCache

    let machOFileInMainCache: MachOFile

    let machOFileInSubCache: MachOFile

    let machOFileInCache: MachOFile

    let machOFile: MachOFile

    let machOImage: MachOImage

    let isEnabledSearchMetadata: Bool = false

    init() throws {
        // Cache
        self.mainCache = try DyldCache(path: .current)
        self.subCache = try required(mainCache.subCaches?.first?.subcache(for: mainCache))

        self.machOFileInMainCache = try #require(mainCache.machOFile(named: .Foundation))
        self.machOFileInSubCache = if #available(macOS 15.5, *) {
            try #require(subCache.machOFile(named: .CodableSwiftUI))
        } else {
            try #require(subCache.machOFile(named: .UIKitCore))
        }

        self.machOFileInCache = try #require(mainCache.machOFile(named: .AttributeGraph))

        // File
        let file = try loadFromFile(named: .iOS_22E238_Simulator_SwiftUICore)
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

    @Test func printCacheFiles() {
        print("******************************[Main Cache]******************************")
        for file in mainCache.machOFiles() {
            print(file.imagePath)
        }
        print("******************************[Sub Cache]*******************************")
        for file in subCache.machOFiles() {
            print(file.imagePath)
        }
    }
    
    @Test func mangledName() async throws {
        try MetadataReader.demangleSymbol(for: .init(offset: 0, stringValue: "_$sSo10CUICatalogC7SwiftUIE9findAsset3key10matchTypes11assetLookupxSgAC10CatalogKeyV_q_AHSSXEtSo08CUINamedJ0CRbzSlR_AC0kE9MatchTypeO7ElementRt_r0_lFSo0M5ColorC_SayANGTB503$s7b3UI5q107V05NamedC033_F70ADAD69423F89598F901BDE477D497LLV14resolveCGColor2inSo0L3RefaSgAA17EnvironmentValuesV_tFSo08M12C0CSgSSXEfU_AbC0Q0V0uQ001_wxyZ10BDE477D497LLVAC0q5CacheL0AXLLVSiTf1nncn_nTf4nnngggn_n"), in: machOFile).print(using: printOptions).print()
    }
}

extension SwiftDumpTests {
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

extension SwiftDumpTests {
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

extension SwiftDumpTests {
    @Test func typesInImage() async throws {
        try await dumpTypes(for: machOImage)
    }

    @Test func protocolsInImage() async throws {
        try await dumpProtocols(for: machOImage)
    }

    @Test func protocolConformancesInImage() async throws {
        try await dumpProtocolConformances(for: machOImage)
    }
}

extension SwiftDumpTests {
    @MachOImageGenerator
    @MainActor
    private func dumpProtocols(for machO: MachOFile) async throws {
        let protocolDescriptors = try machO.swift.protocolDescriptors
        for protocolDescriptor in protocolDescriptors {
            try print(Protocol(descriptor: protocolDescriptor, in: machO).dump(using: printOptions, in: machO).string)
        }
    }

    @MachOImageGenerator
    @MainActor
    private func dumpProtocolConformances(for machO: MachOFile) async throws {
        let protocolConformanceDescriptors = try machO.swift.protocolConformanceDescriptors

        for (index, protocolConformanceDescriptor) in protocolConformanceDescriptors.enumerated() {
            try print(ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machO).dump(using: printOptions, in: machO).string)
        }
    }

    @MachOImageGenerator
    @MainActor
    private func dumpTypes(for machO: MachOFile) async throws {
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

    @MainActor
    private func dumpAssociatedTypes(for machO: MachOFile) async throws {
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
