import Foundation
import MachOKit
import MachOFoundation
import FoundationToolbox
import MachOSwiftSectionC

public enum RuntimeFunctions {
    public static func getTypeByMangledNameInContext(_ mangledTypeName: MangledName, genericContext: UnsafeRawPointer? = nil, genericArguments: UnsafeRawPointer? = nil) throws -> Any.Type? {
        autoBitCast(MachOSwiftSectionC.swift_getTypeByMangledNameInContext(.init(bitPattern: mangledTypeName.startOffset), .init(mangledTypeName.size), nil, nil))
    }

    public static func getTypeByMangledNameInEnvironment(_ mangledTypeName: MangledName, genericContext: UnsafeRawPointer? = nil, genericArguments: UnsafeRawPointer? = nil) throws -> Any.Type? {
        autoBitCast(MachOSwiftSectionC.swift_getTypeByMangledNameInEnvironment(.init(bitPattern: mangledTypeName.startOffset), .init(mangledTypeName.size), nil, nil))
    }

    public static func getTypeByMangledNameInContext(_ mangledTypeName: MangledName, genericContext: UnsafeRawPointer? = nil, genericArguments: UnsafeRawPointer? = nil, in machOImage: MachOImage) throws -> Any.Type? {
        let pointer = try UnsafePointer<UInt8>(bitPattern: Int(bitPattern: machOImage.ptr) + mangledTypeName.startOffset)
        return autoBitCast(MachOSwiftSectionC.swift_getTypeByMangledNameInContext(pointer, .init(mangledTypeName.size), nil, nil))
    }

    public static func getTypeByMangledNameInEnvironment(_ mangledTypeName: MangledName, genericContext: UnsafeRawPointer? = nil, genericArguments: UnsafeRawPointer? = nil, in machOImage: MachOImage) throws -> Any.Type? {
        let pointer = try UnsafePointer<UInt8>(bitPattern: Int(bitPattern: machOImage.ptr) + mangledTypeName.startOffset)
        return autoBitCast(MachOSwiftSectionC.swift_getTypeByMangledNameInEnvironment(pointer, .init(mangledTypeName.size), nil, nil))
    }

    public static func conformsToProtocol(metatype: Any.Type, protocolType: Any.Type) throws -> ProtocolWitnessTable? {
        let existentialTypeMetadataInProcess = try ExistentialTypeMetadata.createInProcess(protocolType)
        let protocols = try existentialTypeMetadataInProcess.protocols()
        guard let protocolRef = protocols.first else { return nil }
        guard !protocolRef.isObjC else { return nil }
        let metadataInProcess = try Metadata.createInProcess(metatype)
        let protocolDescriptor = try protocolRef.swiftProtocol()
        return try conformsToProtocol(metadata: metadataInProcess, protocolDescriptor: protocolDescriptor)
    }
    
    public static func conformsToProtocol(metadata: Metadata, protocolDescriptor: ProtocolDescriptor, in machOImage: MachOImage) throws -> ProtocolWitnessTable? {
        guard let witnessTablePointer = MachOSwiftSectionC.swift_conformsToProtocol(metadata.pointer(in: machOImage), protocolDescriptor.pointer(in: machOImage)) else { return nil }
        let offset = witnessTablePointer.bitPattern.uint - machOImage.ptr.bitPattern.uint
        return try .resolve(from: .init(offset), in: machOImage)
    }
    
    public static func conformsToProtocol(metadata: Metadata, protocolDescriptor: ProtocolDescriptor) throws -> ProtocolWitnessTable? {
        guard let witnessTablePointer = try MachOSwiftSectionC.swift_conformsToProtocol(metadata.asPointer, protocolDescriptor.asPointer) else { return nil }
        return try witnessTablePointer.readWrapperElement()
    }
    
    public static func getAssociatedTypeWitness(request: MetadataRequest, protocolWitnessTable: ProtocolWitnessTable, conformingTypeMetadata: Metadata, baseRequirement: ProtocolBaseRequirement, associatedTypeRequirement: ProtocolRequirement) throws -> MetadataResponse {
        try autoBitCast(MachOSwiftSectionC.swift_getAssociatedTypeWitness(request.rawValue, protocolWitnessTable.asPointer, conformingTypeMetadata.asPointer, baseRequirement.asPointer, associatedTypeRequirement.asPointer))
    }
    
    public static func getAssociatedTypeWitness(request: MetadataRequest, protocolWitnessTable: ProtocolWitnessTable, conformingTypeMetadata: Metadata, baseRequirement: ProtocolBaseRequirement, associatedTypeRequirement: ProtocolRequirement, in machOImage: MachOImage) throws -> MetadataResponse {
        return autoBitCast(MachOSwiftSectionC.swift_getAssociatedTypeWitness(request.rawValue, protocolWitnessTable.pointer(in: machOImage), conformingTypeMetadata.pointer(in: machOImage), baseRequirement.pointer(in: machOImage), associatedTypeRequirement.pointer(in: machOImage)))
    }
}
