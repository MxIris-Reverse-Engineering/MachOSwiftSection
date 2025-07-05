import MachOKit
import MachOMacro
import MachOFoundation

public protocol TypeContextDescriptorProtocol: NamedContextDescriptorProtocol where Layout: TypeContextDescriptorLayout {}

extension TypeContextDescriptorProtocol {
    public func accessFunction<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> Symbol? {
        let ptr = RelativeDirectPointer<Symbol?>(relativeOffset: layout.accessFunctionPtr)
        return try ptr.resolve(from: offset + layout.offset(of: .accessFunctionPtr), in: machO)
    }

    public func fieldDescriptor<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> FieldDescriptor {
        try layout.fieldDescriptor.resolve(from: offset + layout.offset(of: .fieldDescriptor), in: machO)
    }

    public func genericContext<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> GenericContext? {
        guard layout.flags.isGeneric else { return nil }
        return try typeGenericContext(in: machO)?.asGenericContext()
    }

    public func typeGenericContext<MachO: MachORepresentableWithCache & MachOReadable>(in machO: MachO) throws -> TypeGenericContext? {
        guard layout.flags.isGeneric else { return nil }
        return try .init(contextDescriptor: self, in: machO)
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
