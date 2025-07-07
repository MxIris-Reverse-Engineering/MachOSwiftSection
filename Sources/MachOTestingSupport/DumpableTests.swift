import Foundation
import MachOKit
import MachOMacro
import MachOFoundation
import MachOSwiftSection
import SwiftDump

package protocol DumpableTests {
    var isEnabledSearchMetadata: Bool { get }
}

extension DumpableTests {
    package var isEnabledSearchMetadata: Bool { false }

    @MainActor
    package func dumpProtocols<MachO: MachOSwiftSectionRepresentableWithCache>(for machO: MachO) async throws {
        let protocolDescriptors = try machO.swift.protocolDescriptors
        for protocolDescriptor in protocolDescriptors {
            try Protocol(descriptor: protocolDescriptor, in: machO).dump(using: .test, in: machO).string.print()
        }
    }

    @MainActor
    package func dumpProtocolConformances<MachO: MachOSwiftSectionRepresentableWithCache>(for machO: MachO) async throws {
        let protocolConformanceDescriptors = try machO.swift.protocolConformanceDescriptors

        for protocolConformanceDescriptor in protocolConformanceDescriptors {
            try ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machO).dump(using: .test, in: machO).string.print()
        }
    }

    @MainActor
    package func dumpTypes<MachO: MachOSwiftSectionRepresentableWithCache & MachOOffsetConverter>(for machO: MachO, isDetail: Bool = true) async throws {
        let typeContextDescriptors = try machO.swift.typeContextDescriptors
        var metadataFinder: MetadataFinder<MachO>?
        if isEnabledSearchMetadata {
            metadataFinder = MetadataFinder(machO: machO)
        }
        for typeContextDescriptor in typeContextDescriptors {
            switch typeContextDescriptor {
            case let .enum(enumDescriptor):
                do {
                    if isDetail {
                        let enumType = try Enum(descriptor: enumDescriptor, in: machO)
                        try enumType.dump(using: .test, in: machO).string.print()
                    } else {
                        print(enumDescriptor)
                    }
                } catch {
                    error.print()
                }
            case let .struct(structDescriptor):
                do {
                    if isDetail {
                        let structType = try Struct(descriptor: structDescriptor, in: machO)
                        try structType.dump(using: .test, in: machO).string.print()
                    } else {
                        print(structDescriptor)
                    }
                    if let metadata = try metadataFinder?.metadata(for: structDescriptor) as StructMetadata? {
                        try metadata.fieldOffsets(for: structDescriptor, in: machO).print()
                    }
                } catch {
                    error.print()
                }
            case let .class(classDescriptor):
                do {
                    if isDetail {
                        let classType = try Class(descriptor: classDescriptor, in: machO)
                        try classType.dump(using: .test, in: machO).string.print()
                    } else {
                        print(classDescriptor)
                    }
                    if let metadata = try metadataFinder?.metadata(for: classDescriptor) as ClassMetadataObjCInterop? {
                        try metadata.fieldOffsets(for: classDescriptor, in: machO).print()
                    }
                } catch {
                    error.print()
                }
            }
        }
    }

    @MainActor
    package func dumpOpaqueTypes<MachO: MachOSwiftSectionRepresentableWithCache & MachOOffsetConverter>(for machO: MachO) async throws {
        let symbols = SymbolIndexStore.shared.descriptorSymbols(of: .opaqueType, in: machO)
        for symbol in symbols where symbol.offset != 0 {
            var offset = symbol.offset
            
            if let cache = machO.cache {
                offset -= cache.mainCacheHeader.sharedRegionStart.cast()
            }
            let opaqueTypeDescriptor = try machO.readWrapperElement(offset: offset) as OpaqueTypeDescriptor
            let opaqueType = try OpaqueType(descriptor: opaqueTypeDescriptor, in: machO)
            print(opaqueType)
        }
    }

    @MainActor
    package func dumpAssociatedTypes<MachO: MachOSwiftSectionRepresentableWithCache>(for machO: MachO) async throws {
        let associatedTypeDescriptors = try machO.swift.associatedTypeDescriptors
        for associatedTypeDescriptor in associatedTypeDescriptors {
            try AssociatedType(descriptor: associatedTypeDescriptor, in: machO).dump(using: .test, in: machO).string.print()
        }
    }

    @MainActor
    package func dumpBuiltinTypes<MachO: MachOSwiftSectionRepresentableWithCache>(for machO: MachO) async throws {
        let descriptors = try machO.swift.builtinTypeDescriptors
        for descriptor in descriptors {
            try print(BuiltinType(descriptor: descriptor, in: machO))
        }
    }
}
