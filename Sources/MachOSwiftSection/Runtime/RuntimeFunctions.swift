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

    public static func getTypeByMangledNameInContext(_ mangledTypeName: MangledName, genericContext: UnsafeRawPointer? = nil, genericArguments: UnsafeRawPointer? = nil, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> Any.Type? {
        guard let machOImage = machO as? MachOImage else { return nil }
        let pointer = try UnsafePointer<UInt8>(bitPattern: Int(bitPattern: machOImage.ptr) + mangledTypeName.startOffset)
        return autoBitCast(MachOSwiftSectionC.swift_getTypeByMangledNameInContext(pointer, .init(mangledTypeName.size), nil, nil))
    }

    public static func getTypeByMangledNameInEnvironment(_ mangledTypeName: MangledName, genericContext: UnsafeRawPointer? = nil, genericArguments: UnsafeRawPointer? = nil, in machO: some MachOSwiftSectionRepresentableWithCache) throws -> Any.Type? {
        guard let machOImage = machO as? MachOImage else { return nil }
        let pointer = try UnsafePointer<UInt8>(bitPattern: Int(bitPattern: machOImage.ptr) + mangledTypeName.startOffset)
        return autoBitCast(MachOSwiftSectionC.swift_getTypeByMangledNameInEnvironment(pointer, .init(mangledTypeName.size), nil, nil))
    }

    public static func conformsToProtocol(metadata: Any.Type, existentialTypeMetadata: Any.Type) throws -> ProtocolWitnessTable? {
        let existentialTypeMetadataInProcess = try ExistentialTypeMetadata.createInProcess(existentialTypeMetadata)
        let protocols = try existentialTypeMetadataInProcess.protocols()
        guard let protocolRef = protocols.first else { return nil }
        guard !protocolRef.isObjC else { return nil }
        let metadataInProcess = try Metadata.createInProcess(metadata)
        let protocolDescriptor = try protocolRef.swiftProtocol()
        return try conformsToProtocol(metadata: metadataInProcess, protocolDescriptor: protocolDescriptor)
    }
    
    public static func conformsToProtocol(metadata: Metadata, protocolDescriptor: ProtocolDescriptor) throws -> ProtocolWitnessTable? {
        let metadataPointer = try metadata.asPointer
        let protocolPointer = try protocolDescriptor.asPointer
        guard let witnessTablePointer = MachOSwiftSectionC.swift_conformsToProtocol(metadataPointer, protocolPointer) else { return nil }
        return try witnessTablePointer.readWrapperElement()
    }
    
    public static func getAssociatedTypeWitness(request: MetadataRequest, protocolWitnessTable: ProtocolWitnessTable, conformingTypeMetadata: Metadata, baseRequirement: ProtocolRequirement, associatedTypeRequirement: ProtocolRequirement) throws -> MetadataResponse {
        try autoBitCast(MachOSwiftSectionC.swift_getAssociatedTypeWitness(request.rawValue, protocolWitnessTable.asPointer, conformingTypeMetadata.asPointer, baseRequirement.asPointer, associatedTypeRequirement.asPointer))
    }
}
