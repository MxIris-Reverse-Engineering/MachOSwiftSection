import MachOKit
import MachOBase

public protocol TypeContextDescriptorProtocol: NamedContextDescriptorProtocol where Layout: TypeContextDescriptorLayout {}

// MARK: - ReadingContext Support

extension TypeContextDescriptorProtocol {
    public func genericContext(in context: some ReadingContext) throws -> GenericContext? {
        guard layout.flags.isGeneric else { return nil }
        return try typeGenericContext(in: context)?.asGenericContext()
    }

    public func typeGenericContext(in context: some ReadingContext) throws -> TypeGenericContext? {
        guard layout.flags.isGeneric else { return nil }
        return try .init(contextDescriptor: self, in: context)
    }

    public func fieldDescriptor(in context: some ReadingContext) throws -> FieldDescriptor {
        let address = try context.addressFromOffset(offset + layout.offset(of: .fieldDescriptor))
        return try layout.fieldDescriptor.resolve(at: address, in: context)
    }

    /// The type's metadata accessor, or `nil` when `context` is not mapped
    /// into this process (a `MachOContext` over a `MachOFile`). The target is
    /// computed from the relative offset already in `layout`, so a context
    /// that cannot vend a runtime pointer answers `nil` without reading.
    public func metadataAccessorFunction(in context: some ReadingContext) throws -> MetadataAccessorFunction? {
        let fieldAddress = try context.addressFromOffset(offset + layout.offset(of: .accessFunctionPtr))
        let targetAddress = try layout.accessFunctionPtr.resolveDirectAddress(at: fieldAddress, in: context)
        return try context.runtimePointer(at: targetAddress).map { MetadataAccessorFunction(ptr: $0) }
    }
}

extension TypeContextDescriptorProtocol {
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

// MARK: - Type import info

extension TypeContextDescriptorProtocol {
    /// The C-import identity components that follow the descriptor's name,
    /// or `nil` when `hasImportInfo` is not set. See ``TypeImportInfo``.
    public func typeImportInfo(in context: some ReadingContext) throws -> TypeImportInfo? {
        guard hasImportInfo else { return nil }
        let nameFieldAddress = try context.addressFromOffset(offset + layout.offset(of: .name))
        var cursor = try layout.name.resolveDirectAddress(at: nameFieldAddress, in: context)
        var components: [String] = []
        // The first string is the user-facing name the descriptor's `name`
        // already vends; the components follow it, and an empty string ends
        // the sequence.
        var current = try context.readString(at: cursor)
        while true {
            cursor = context.advanceAddress(cursor, by: current.utf8.count + 1)
            current = try context.readString(at: cursor)
            if current.isEmpty { break }
            components.append(current)
        }
        return TypeImportInfo(components: components)
    }
}
