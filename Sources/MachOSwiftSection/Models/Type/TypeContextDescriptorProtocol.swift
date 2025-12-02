import MachOKit
import MachOFoundation

public protocol TypeContextDescriptorProtocol: NamedContextDescriptorProtocol where Layout: TypeContextDescriptorLayout {}

extension TypeContextDescriptorProtocol {
    public func metadataAccessor<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> MetadataAccessor? {
        guard let machOImage = machO as? MachOImage else { return nil }
        let offset = layout.accessFunctionPtr.resolveDirectOffset(from: offset + layout.offset(of: .accessFunctionPtr))
        return MetadataAccessor(raw: machOImage.ptr + UnsafeRawPointer.Stride(offset))
    }

    public func fieldDescriptor<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> FieldDescriptor {
        try layout.fieldDescriptor.resolve(from: offset + layout.offset(of: .fieldDescriptor), in: machO)
    }

    public func genericContext<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> GenericContext? {
        guard layout.flags.isGeneric else { return nil }
        return try typeGenericContext(in: machO)?.asGenericContext()
    }

    public func typeGenericContext<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> TypeGenericContext? {
        guard layout.flags.isGeneric else { return nil }
        return try .init(contextDescriptor: self, in: machO)
    }

    public func metadataAccessor() throws -> MetadataAccessor? {
        return try layout.accessFunctionPtr.resolve(from: layout.pointer(from: asPointer, of: .accessFunctionPtr))
    }

    public func fieldDescriptor() throws -> FieldDescriptor {
        return try layout.fieldDescriptor.resolve(from: layout.pointer(from: asPointer, of: .fieldDescriptor))
    }

    public func genericContext() throws -> GenericContext? {
        guard layout.flags.isGeneric else { return nil }
        return try typeGenericContext()?.asGenericContext()
    }

    public func typeGenericContext() throws -> TypeGenericContext? {
        guard layout.flags.isGeneric else { return nil }
        return try .init(contextDescriptor: self)
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
