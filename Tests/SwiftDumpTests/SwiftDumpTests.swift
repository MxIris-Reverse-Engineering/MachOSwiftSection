import Foundation
import Testing
import MachOKit
import MachOMacro
@testable import MachOSwiftSection
@testable import SwiftDump

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
        let arch = "arm64e"
        let mainCachePath = "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_\(arch)"
        let subCachePath = "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_\(arch).01"
        let mainCacheURL = URL(fileURLWithPath: mainCachePath)
        let subCacheURL = URL(fileURLWithPath: subCachePath)
        self.mainCache = try DyldCache(url: mainCacheURL)
        self.subCache = try DyldCache(subcacheUrl: subCacheURL, mainCacheHeader: mainCache.mainCacheHeader)

        self.machOFileInMainCache = try #require(mainCache.machOFile(named: .SwiftUI))

        self.machOFileInSubCache = if #available(macOS 15.5, *) {
            try #require(subCache.machOFile(named: .CodableSwiftUI))
        } else {
            try #require(subCache.machOFile(named: .AAAFoundationSwift))
        }

        self.machOFileInCache = try #require(mainCache.machOFile(named: .Foundation))

        // File
//        let path = "/Library/Developer/CoreSimulator/Volumes/iOS_22E238/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.4.simruntime/Contents/Resources/RuntimeRoot/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore"
        let path = "/System/Applications/iPhone Mirroring.app/Contents/Frameworks/ScreenContinuityUI.framework/Versions/A/ScreenContinuityUI"
//        let path = "/Applications/SourceEdit.app/Contents/Frameworks/SourceEditor.framework/Versions/A/SourceEditor"
        let url = URL(fileURLWithPath: path)
        let file = try MachOKit.loadFromFile(url: url)
        switch file {
        case let .fat(fatFile):
            self.machOFile = try #require(fatFile.machOFiles().first(where: { $0.header.cpu.type == .x86_64 }))
        case let .machO(machO):
            self.machOFile = machO
        @unknown default:
            fatalError()
        }

        // Image

        self.machOImage = try #require(MachOImage(name: "Foundation"))
    }

    @Test func printCacheFiles() {
        print("Main Cache")
        for file in mainCache.machOFiles() {
            print(file.imagePath)
        }
        print("Sub Cache")
        for file in subCache.machOFiles() {
            print(file.imagePath)
        }
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
        let protocolDescriptors = try #require(machO.swift.protocolDescriptors)
        for protocolDescriptor in protocolDescriptors {
            try print(Protocol(descriptor: protocolDescriptor, in: machO).dump(using: printOptions, in: machO))
        }
    }

    @MachOImageGenerator
    @MainActor
    private func dumpProtocolConformances(for machO: MachOFile) async throws {
        let protocolConformanceDescriptors = try #require(machO.swift.protocolConformanceDescriptors)

        for (index, protocolConformanceDescriptor) in protocolConformanceDescriptors.enumerated() {
            print(index)
            try print(ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machO).dump(using: printOptions, in: machO))
        }
    }

    @MachOImageGenerator
    @MainActor
    private func dumpTypes(for machO: MachOFile) async throws {
        let typeContextDescriptors = try #require(machO.swift.typeContextDescriptors)
        var metadataFinder: MetadataFinder<MachOFile>?
        if isEnabledSearchMetadata {
            metadataFinder = MetadataFinder(machO: machO)
        }
        for typeContextDescriptor in typeContextDescriptors {
            switch typeContextDescriptor {
            case let .type(typeContextDescriptorWrapper):
                switch typeContextDescriptorWrapper {
                case let .enum(enumDescriptor):
                    let enumType = try Enum(descriptor: enumDescriptor, in: machO)
                    try print(enumType.dump(using: printOptions, in: machO))
                case let .struct(structDescriptor):
                    let structType = try Struct(descriptor: structDescriptor, in: machO)
                    try print(structType.dump(using: printOptions, in: machO))
                    if let metadata = try metadataFinder?.metadata(for: structDescriptor) as StructMetadata? {
                        print(try metadata.fieldOffsets(for: structDescriptor, in: machO))
                    }
                case let .class(classDescriptor):
                    let classType = try Class(descriptor: classDescriptor, in: machO)
                    try print(classType.dump(using: printOptions, in: machO))
                    if let metadata = try metadataFinder?.metadata(for: classDescriptor) as ClassMetadataObjCInterop? {
                        print(try metadata.fieldOffsets(for: classDescriptor, in: machO))
                    }
                }
            default:
                break
            }
        }
    }

    @MainActor
    private func dumpAssociatedTypes(for machO: MachOFile) async throws {
        let associatedTypeDescriptors = try #require(machO.swift.associatedTypeDescriptors)
        for associatedTypeDescriptor in associatedTypeDescriptors {
            try print(AssociatedType(descriptor: associatedTypeDescriptor, in: machO).dump(using: printOptions, in: machO))
        }
    }
}
