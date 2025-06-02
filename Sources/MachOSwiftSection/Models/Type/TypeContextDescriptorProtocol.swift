import MachOKit
import MachOMacro
import MachOFoundation

public protocol TypeContextDescriptorProtocol: NamedContextDescriptorProtocol where Layout: TypeContextDescriptorLayout {}

@MachOImageAllMembersGenerator
extension TypeContextDescriptorProtocol {
    
    public func accessFunction(in machOFile: MachOFile) throws -> MachOSymbol? {
        let ptr = RelativeDirectPointer<MachOSymbol?>(relativeOffset: layout.accessFunctionPtr)
        return try ptr.resolve(from: offset + layout.offset(of: .accessFunctionPtr), in: machOFile)
    }
    
    public func fieldDescriptor(in machOFile: MachOFile) throws -> FieldDescriptor {
        try layout.fieldDescriptor.resolve(from: offset + layout.offset(of: .fieldDescriptor), in: machOFile)
    }

    public func genericContext(in machO: MachOFile) throws -> GenericContext? {
        guard layout.flags.isGeneric else { return nil }
        return try typeGenericContext(in: machO)?.asGenericContext()
    }
    
    public func typeGenericContext(in machOFile: MachOFile) throws -> TypeGenericContext? {
        guard layout.flags.isGeneric else { return nil }
        return try .init(contextDescriptor: self, in: machOFile)
    }
    
    public var hasSingletonMetadataInitialization: Bool {
        return layout.flags.kindSpecificFlags?.typeFlags?.hasSingletonMetadataInitialization ?? false
    }
    
    public var hasForeignMetadataInitialization: Bool {
        return layout.flags.kindSpecificFlags?.typeFlags?.hasForeignMetadataInitialization ?? false
    }
    
    public var hasImportInfo: Bool {
        return layout.flags.kindSpecificFlags?.typeFlags?.hasImportInfo ?? false
    }
    
    public var hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer: Bool {
        return layout.flags.kindSpecificFlags?.typeFlags?.hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer ?? false
    }
    
    public var hasLayoutString: Bool {
        return layout.flags.kindSpecificFlags?.typeFlags?.hasLayoutString ?? false
    }
    
    public var hasCanonicalMetadataPrespecializations: Bool {
        return layout.flags.contains(.isGeneric) && hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer
    }
    
    public var hasSingletonMetadataPointer: Bool {
        return !layout.flags.contains(.isGeneric) && hasCanonicalMetadataPrespecializationsOrSingletonMetadataPointer
    }
}

func align(address: UInt64, alignment: UInt64) -> UInt64 {
    (address + alignment - 1) & ~(alignment - 1)
}
