import Testing
import Foundation
import MachOKit
import MachOMacro
@testable import MachOSwiftSection
@testable import SwiftDump

@Suite
struct SwiftDumpTests {
    let mainCache: DyldCache

    let mainCacheMachOFileInCache: MachOFile

    let subCache: DyldCache

    let subCacheMachOFileInCache: MachOFile

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

        self.mainCacheMachOFileInCache = mainCache.machOFiles().first(where: {
//            $0.imagePath.contains("/AppKit")
            $0.imagePath.contains("/SwiftUI")
//            $0.imagePath.contains("/Foundation")
        })!

        self.subCacheMachOFileInCache = subCache.machOFiles().first(where: {
            $0.imagePath.contains("/CodableSwiftUI")
        })!

        self.machOFileInCache = (mainCache.machOFiles().map { $0 } + subCache.machOFiles().map { $0 }).first {
            $0.imagePath.contains("/Foundation")
        }!

        // File
        let path = "/Library/Developer/CoreSimulator/Volumes/iOS_22E238/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 18.4.simruntime/Contents/Resources/RuntimeRoot/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore"
        //        let path = "/System/Applications/iPhone Mirroring.app/Contents/Frameworks/ScreenContinuityUI.framework/Versions/A/ScreenContinuityUI"
//              let path = "/Applications/SourceEdit.app/Contents/Frameworks/SourceEditor.framework/Versions/A/SourceEditor"
        let url = URL(fileURLWithPath: path)
        let file = try MachOKit.loadFromFile(url: url)
        switch file {
        case .fat(let fatFile):
            self.machOFile = try fatFile.machOFiles().first(where: { $0.header.cpu.type == .x86_64 })!
        case .machO(let machO):
            self.machOFile = machO
        @unknown default:
            fatalError()
        }

        // Image

        self.machOImage = try required(MachOImage(name: "Foundation"))
    }
}

extension SwiftDumpTests {
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

    @Test func protocolNamesInCacheFile() async throws {
        let protocols = try required(subCacheMachOFileInCache.swift.protocolDescriptors)
        for proto in protocols {
            try print(proto.name(in: subCacheMachOFileInCache))
        }
    }

    @Test func typesInCacheFile() async throws {
        try await dumpTypes(for: machOFileInCache)
    }

    @Test func typesInMainCacheFile() async throws {
        try await dumpTypes(for: mainCacheMachOFileInCache)
    }

    @Test func typesInSubCacheFile() async throws {
        try await dumpTypes(for: subCacheMachOFileInCache)
    }
    
    @Test func protocolsInCacheFile() async throws {
        try await dumpProtocols(for: machOFileInCache)
    }

    @Test func protocolConformancesInCacheFile() async throws {
        try await dumpProtocolConformances(for: machOFileInCache)
    }

    @Test func associatedTypesInCacheFile() async throws {
        try await dumpAssociatedTypes(for: machOFileInCache)
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
        let protocolDescriptors = try required(machO.swift.protocolDescriptors)
        for protocolDescriptor in protocolDescriptors {
            try print(Protocol(descriptor: protocolDescriptor, in: machO).dump(using: printOptions, in: machO))
        }
    }

    @MachOImageGenerator
    @MainActor
    private func dumpProtocolConformances(for machO: MachOFile) async throws {
        let protocolConformanceDescriptors = try required(machO.swift.protocolConformanceDescriptors)

        for (index, protocolConformanceDescriptor) in protocolConformanceDescriptors.enumerated() {
            print(index)
            try print(ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machO).dump(using: printOptions, in: machO))
        }
    }

    @MachOImageGenerator
    @MainActor
    private func dumpTypes(for machO: MachOFile) async throws {
        let typeContextDescriptors = try required(machO.swift.typeContextDescriptors)
//        let metadataFinder = MetadataFinder(machO: machO)
        for typeContextDescriptor in typeContextDescriptors {
            switch typeContextDescriptor {
            case .type(let typeContextDescriptorWrapper):
                switch typeContextDescriptorWrapper {
                case .enum(let enumDescriptor):
                    let enumType = try Enum(descriptor: enumDescriptor, in: machO)
                    try print(enumType.dump(using: printOptions, in: machO))
                case .struct(let structDescriptor):
                    let structType = try Struct(descriptor: structDescriptor, in: machO)
//                    try print(metadataFinder.metadata(for: structDescriptor) as StructMetadata?)
                    try print(structType.dump(using: printOptions, in: machO))
                case .class(let classDescriptor):
                    let classType = try Class(descriptor: classDescriptor, in: machO)
                    try print(classType.dump(using: printOptions, in: machO))
//                    try print(metadataFinder.metadata(for: classDescriptor) as ClassMetadataObjCInterop?)
                }
//                print("")
            case .protocol /* (let protocolDescriptor) */:
                break
            case .anonymous /* (let anonymousContextDescriptor) */:
                break
            case .extension /* (let extensionContextDescriptor) */:
                break
            case .module /* (let moduleContextDescriptor) */:
                break
            case .opaqueType /* (let opaqueTypeDescriptor) */:
//                let opaqueType = try OpaqueType(descriptor: opaqueTypeDescriptor, in: machO)
//                try print(opaqueType.dump(using: printOptions, in: machO))
                break
            }
        }
    }

    @MainActor
    private func dumpAssociatedTypes(for machO: MachOFile) async throws {
        let associatedTypeDescriptors = try required(machO.swift.associatedTypeDescriptors)
        for associatedTypeDescriptor in associatedTypeDescriptors {
            try print(AssociatedType(descriptor: associatedTypeDescriptor, in: machO).dump(using: printOptions, in: machO))
        }
    }
}
