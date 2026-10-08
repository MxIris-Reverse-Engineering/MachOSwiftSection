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

// MARK: - Deprecated Mach-O and pointer forms

// `ContextDescriptorProtocol` declares both old `genericContext` forms too.
// They stay here so a call on a type descriptor binds to the same declaration
// as before. The forward goes through the `ContextDescriptorProtocol`
// requirement, whose witness for a type descriptor is this protocol's
// `genericContext(in:)` — the one that reads the type generic context header.
extension TypeContextDescriptorProtocol {
    @available(*, deprecated, message: "Pass a ReadingContext: metadataAccessorFunction(in: machO.context).")
    public func metadataAccessorFunction(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MetadataAccessorFunction? {
        try metadataAccessorFunction(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: fieldDescriptor(in: machO.context).")
    public func fieldDescriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> FieldDescriptor {
        try fieldDescriptor(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: genericContext(in: machO.context).")
    public func genericContext(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> GenericContext? {
        try genericContext(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: typeGenericContext(in: machO.context).")
    public func typeGenericContext(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> TypeGenericContext? {
        try typeGenericContext(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: typeImportInfo(in: machO.context).")
    public func typeImportInfo(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> TypeImportInfo? {
        try typeImportInfo(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: metadataAccessorFunction(in: .inProcess).")
    public func metadataAccessorFunction() throws -> MetadataAccessorFunction? {
        try metadataAccessorFunction(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: fieldDescriptor(in: .inProcess).")
    public func fieldDescriptor() throws -> FieldDescriptor {
        try fieldDescriptor(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: genericContext(in: .inProcess).")
    public func genericContext() throws -> GenericContext? {
        try genericContext(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: typeGenericContext(in: .inProcess).")
    public func typeGenericContext() throws -> TypeGenericContext? {
        try typeGenericContext(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: typeImportInfo(in: .inProcess).")
    public func typeImportInfo() throws -> TypeImportInfo? {
        try typeImportInfo(in: InProcessContext.shared)
    }
}
