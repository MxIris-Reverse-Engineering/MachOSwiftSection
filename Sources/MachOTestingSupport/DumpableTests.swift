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
    
    @MachOImageGenerator
    @MainActor
    package func dumpProtocols(for machO: MachOFile) async throws {
        let protocolDescriptors = try machO.swift.protocolDescriptors
        for protocolDescriptor in protocolDescriptors {
            try Protocol(descriptor: protocolDescriptor, in: machO).dump(using: .test, in: machO).string.print()
        }
    }

    @MachOImageGenerator
    @MainActor
    package func dumpProtocolConformances(for machO: MachOFile) async throws {
        let protocolConformanceDescriptors = try machO.swift.protocolConformanceDescriptors

        for protocolConformanceDescriptor in protocolConformanceDescriptors {
            try ProtocolConformance(descriptor: protocolConformanceDescriptor, in: machO).dump(using: .test, in: machO).string.print()
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
                        try enumType.dump(using: .test, in: machO).string.print()
                    } catch {
                        error.print()
                    }
                case .struct(let structDescriptor):
                    do {
                        let structType = try Struct(descriptor: structDescriptor, in: machO)
                        try structType.dump(using: .test, in: machO).string.print()
                        if let metadata = try metadataFinder?.metadata(for: structDescriptor) as StructMetadata? {
                            try metadata.fieldOffsets(for: structDescriptor, in: machO).print()
                        }
                    } catch {
                        error.print()
                    }
                case .class(let classDescriptor):
                    do {
                        let classType = try Class(descriptor: classDescriptor, in: machO)
                        try classType.dump(using: .test, in: machO).string.print()
                        if let metadata = try metadataFinder?.metadata(for: classDescriptor) as ClassMetadataObjCInterop? {
                            try metadata.fieldOffsets(for: classDescriptor, in: machO).print()
                        }
                    } catch {
                        error.print()
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
            try AssociatedType(descriptor: associatedTypeDescriptor, in: machO).dump(using: .test, in: machO).string.print()
        }
    }
    
    
    @MachOImageGenerator
    @MainActor
    package func dumpBuiltinTypes(for machO: MachOFile) async throws {
        let descriptors = try machO.swift.builtinTypeDescriptors
        for descriptor in descriptors {
            print(try BuiltinType(descriptor: descriptor, in: machO))
        }
    }
}


