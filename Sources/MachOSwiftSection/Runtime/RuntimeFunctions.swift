import Foundation
import MachOKit
import MachOFoundation
import FoundationToolbox
import MachOSwiftSectionC

public enum RuntimeFunctions {
    public static func getTypeByMangledNameInContext(_ mangledTypeName: MangledName, genericContext: UnsafeRawPointer? = nil, genericArguments: UnsafeRawPointer? = nil) throws -> Any.Type? {
        autoBitCast(MachOSwiftSectionC.swift_getTypeByMangledNameInContext(.init(bitPattern: mangledTypeName.startOffset), .init(mangledTypeName.size), genericContext, genericArguments))
    }

    public static func getTypeByMangledNameInEnvironment(_ mangledTypeName: MangledName, genericContext: UnsafeRawPointer? = nil, genericArguments: UnsafeRawPointer? = nil) throws -> Any.Type? {
        autoBitCast(MachOSwiftSectionC.swift_getTypeByMangledNameInEnvironment(.init(bitPattern: mangledTypeName.startOffset), .init(mangledTypeName.size), genericContext, genericArguments))
    }

    public static func getTypeByMangledNameInContext(_ mangledTypeName: MangledName, genericContext: UnsafeRawPointer? = nil, genericArguments: UnsafeRawPointer? = nil, in machOImage: MachOImage) throws -> Any.Type? {
        let pointer = try UnsafePointer<UInt8>(bitPattern: Int(bitPattern: machOImage.ptr) + mangledTypeName.startOffset)
        return autoBitCast(MachOSwiftSectionC.swift_getTypeByMangledNameInContext(pointer, .init(mangledTypeName.size), genericContext, genericArguments))
    }

    public static func getTypeByMangledNameInEnvironment(_ mangledTypeName: MangledName, genericContext: UnsafeRawPointer? = nil, genericArguments: UnsafeRawPointer? = nil, in machOImage: MachOImage) throws -> Any.Type? {
        let pointer = try UnsafePointer<UInt8>(bitPattern: Int(bitPattern: machOImage.ptr) + mangledTypeName.startOffset)
        return autoBitCast(MachOSwiftSectionC.swift_getTypeByMangledNameInEnvironment(pointer, .init(mangledTypeName.size), genericContext, genericArguments))
    }

    /// Resolves a mangled type name interpreted within the generic context of a
    /// specialized in-process value-type metadata.
    ///
    /// The runtime's `swift_getTypeByMangledNameInContext` expects two pieces of
    /// information: the enclosing context descriptor and the array of generic
    /// argument metadata pointers. Both can be derived from a specialized
    /// in-process metadata pointer alone:
    ///   - descriptor: stored directly inside the metadata header.
    ///   - generic arguments: laid out immediately after the metadata header
    ///     (offset = `sizeof(metadata header) / sizeof(StoredPointer)` words,
    ///      mirroring `TargetStructMetadata::getGenericArgumentOffset()` /
    ///      `TargetEnumMetadata::getGenericArgumentOffset()` in the Swift runtime).
    ///
    /// `metadata` must have been constructed in-process (e.g. via
    /// `createInProcess`) so that `asPointer` and `layout.descriptor.address`
    /// refer to live memory.
    public static func getTypeByMangledNameInContext<Metadata: ValueMetadataProtocol>(_ mangledTypeName: MangledName, specializedFrom metadata: Metadata, in machOImage: MachOImage) throws -> Any.Type? {
        let metadataPointer = try metadata.asPointer
        let descriptorPointer = try UnsafeRawPointer(bitPattern: UInt(metadata.layout.descriptor.address))
        let genericArgumentsPointer = metadataPointer.advanced(by: MemoryLayout<Metadata.Layout>.size)
        return try getTypeByMangledNameInContext(mangledTypeName, genericContext: descriptorPointer, genericArguments: genericArgumentsPointer, in: machOImage)
    }

    /// In-process variant of `getTypeByMangledNameInContext(_:specializedFrom:in:)`.
    ///
    /// Use this when the mangled name was read from in-process descriptor
    /// memory (e.g. via the no-arg `mangledTypeName()` reads of nested
    /// field records). `mangledTypeName.startOffset` is interpreted as an
    /// absolute in-process pointer rather than a Mach-O file offset.
    public static func getTypeByMangledNameInContext<Metadata: ValueMetadataProtocol>(_ mangledTypeName: MangledName, specializedFrom metadata: Metadata) throws -> Any.Type? {
        let metadataPointer = try metadata.asPointer
        let descriptorPointer = try UnsafeRawPointer(bitPattern: UInt(metadata.layout.descriptor.address))
        let genericArgumentsPointer = metadataPointer.advanced(by: MemoryLayout<Metadata.Layout>.size)
        return try getTypeByMangledNameInContext(mangledTypeName, genericContext: descriptorPointer, genericArguments: genericArgumentsPointer)
    }

    /// Class-specialized variant of `getTypeByMangledNameInContext(_:specializedFrom:in:)`.
    ///
    /// Class metadata's generic-argument offset is not a constant. Swift's
    /// runtime computes it from the descriptor (`TargetClassDescriptor::getGenericArgumentOffset`)
    /// — for non-resilient superclasses it derives from the `(metadataNegativeSize,
    /// metadataPositiveSize, numImmediateMembers, areImmediateMembersNegative)`
    /// quartet; for resilient superclasses it reads the runtime-populated
    /// `StoredClassMetadataBounds.immediateMembersOffset` (in bytes) attached
    /// to the descriptor. We follow the same branching here so the resulting
    /// `genericArguments` pointer lands on the inline argument array regardless
    /// of layout.
    ///
    /// Returns `nil` if the metadata's descriptor pointer is null (pure ObjC
    /// class instance — no Swift descriptor to substitute against).
    public static func getTypeByMangledNameInContext(_ mangledTypeName: MangledName, specializedFrom metadata: ClassMetadataObjCInterop, in machOImage: MachOImage) throws -> Any.Type? {
        guard let descriptor = try metadata.descriptor() else { return nil }
        let metadataPointer = try metadata.asPointer
        let descriptorPointer = try UnsafeRawPointer(bitPattern: UInt(metadata.layout.descriptor.address))
        let genericArgumentOffsetWords: Int
        if descriptor.hasResilientSuperclass {
            // The runtime fills `immediateMembersOffset` (bytes) when the
            // class metadata is realized; by the time we hold the in-process
            // metadata pointer here, it is current.
            let bounds = try descriptor.resilientMetadataBounds()
            genericArgumentOffsetWords = Int(bounds.layout.immediateMembersOffset) / MemoryLayout<StoredPointer>.size
        } else {
            genericArgumentOffsetWords = Int(descriptor.nonResilientImmediateMembersOffset)
        }
        let genericArgumentsPointer = metadataPointer.advanced(by: genericArgumentOffsetWords * MemoryLayout<StoredPointer>.size)
        return try getTypeByMangledNameInContext(mangledTypeName, genericContext: descriptorPointer, genericArguments: genericArgumentsPointer, in: machOImage)
    }

    /// In-process variant of the class-specialized
    /// `getTypeByMangledNameInContext(_:specializedFrom:in:)`. See the
    /// value-type sibling above for the rationale.
    public static func getTypeByMangledNameInContext(_ mangledTypeName: MangledName, specializedFrom metadata: ClassMetadataObjCInterop) throws -> Any.Type? {
        guard let descriptor = try metadata.descriptor() else { return nil }
        let metadataPointer = try metadata.asPointer
        let descriptorPointer = try UnsafeRawPointer(bitPattern: UInt(metadata.layout.descriptor.address))
        let genericArgumentOffsetWords: Int
        if descriptor.hasResilientSuperclass {
            let bounds = try descriptor.resilientMetadataBounds()
            genericArgumentOffsetWords = Int(bounds.layout.immediateMembersOffset) / MemoryLayout<StoredPointer>.size
        } else {
            genericArgumentOffsetWords = Int(descriptor.nonResilientImmediateMembersOffset)
        }
        let genericArgumentsPointer = metadataPointer.advanced(by: genericArgumentOffsetWords * MemoryLayout<StoredPointer>.size)
        return try getTypeByMangledNameInContext(mangledTypeName, genericContext: descriptorPointer, genericArguments: genericArgumentsPointer)
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
