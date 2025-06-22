import Foundation
import MachOKit
import MachOMacro
import MachOFoundation
import MachOSwiftSection
import SwiftDump
import MachOTestingSupport

package protocol DumpableTest {
    var isEnabledSearchMetadata: Bool { get }
}

extension DumpableTest {
    @MachOImageGenerator
    @MainActor
    package func dumpProtocols(for machO: MachOFile) async throws {
        let protocolDescriptors = try machO.swift.protocolDescriptors
        for protocolDescriptor in protocolDescriptors {
            try print(Protocol(descriptor: protocolDescriptor, in: machO).dump(using: .test, in: machO).string)
        }
    }

    @MachOImageGenerator
    @MainActor
    package func dumpProtocolConformances(for machO: MachOFile) async throws {
        let protocolConformanceDescriptors = try machO.swift.protocolConformanceDescriptors

        for protocolConformanceDescriptor in protocolConformanceDescriptors {
            try print(ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machO).dump(using: .test, in: machO).string)
        }
    }

    @MachOImageGenerator
    @MainActor
    package func dumpTypes(for machO: MachOFile) async throws {
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
                    do {
                        let enumType = try Enum(descriptor: enumDescriptor, in: machO)
                        try print(enumType.dump(using: .test, in: machO).string)
                    } catch {
                        print(error)
                    }
                case .struct(let structDescriptor):
                    do {
                        let structType = try Struct(descriptor: structDescriptor, in: machO)
                        try print(structType.dump(using: .test, in: machO).string)
                        if let metadata = try metadataFinder?.metadata(for: structDescriptor) as StructMetadata? {
                            try print(metadata.fieldOffsets(for: structDescriptor, in: machO))
                        }
                    } catch {
                        print(error)
                    }
                case .class(let classDescriptor):
                    do {
                        let classType = try Class(descriptor: classDescriptor, in: machO)
                        try print(classType.dump(using: .test, in: machO).string)
                        if let metadata = try metadataFinder?.metadata(for: classDescriptor) as ClassMetadataObjCInterop? {
                            try print(metadata.fieldOffsets(for: classDescriptor, in: machO))
                        }
                    } catch {
                        print(error)
                    }
                }
            default:
                break
            }
        }
    }

    @MachOImageGenerator
    @MainActor
    package func dumpAssociatedTypes(for machO: MachOFile) async throws {
        let associatedTypeDescriptors = try machO.swift.associatedTypeDescriptors
        for associatedTypeDescriptor in associatedTypeDescriptors {
            try print(AssociatedType(descriptor: associatedTypeDescriptor, in: machO).dump(using: .test, in: machO).string)
        }
    }
}


