import MachOKit
import MachOBase

public protocol TypeContextDescriptorProtocol: NamedContextDescriptorProtocol where Layout: TypeContextDescriptorLayout {}

extension TypeContextDescriptorProtocol {
    public func metadataAccessorFunction<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> MetadataAccessorFunction? {
        guard let machOImage = machO as? MachOImage else { return nil }
        let offset = layout.accessFunctionPtr.resolveDirectOffset(from: offset + layout.offset(of: .accessFunctionPtr))
        return .init(ptr: machOImage.ptr + UnsafeRawPointer.Stride(offset))
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
}

extension TypeContextDescriptorProtocol {
    public func metadataAccessorFunction() throws -> MetadataAccessorFunction? {
        let ptr = try layout.pointer(from: asPointer, of: .accessFunctionPtr)
        return try .init(ptr: layout.accessFunctionPtr.resolveDirectOffset(from: ptr))
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
}

// MARK: - ReadingContext Support

extension TypeContextDescriptorProtocol {
    public func genericContext<Context: ReadingContext>(in context: Context) throws -> GenericContext? {
        guard layout.flags.isGeneric else { return nil }
        return try typeGenericContext(in: context)?.asGenericContext()
    }

    public func typeGenericContext<Context: ReadingContext>(in context: Context) throws -> TypeGenericContext? {
        guard layout.flags.isGeneric else { return nil }
        return try .init(contextDescriptor: self, in: context)
    }

    public func fieldDescriptor<Context: ReadingContext>(in context: Context) throws -> FieldDescriptor {
        let address = try context.addressFromOffset(offset + layout.offset(of: .fieldDescriptor))
        return try layout.fieldDescriptor.resolve(at: address, in: context)
    }

    public func metadataAccessorFunction<Context: ReadingContext>(in context: Context) throws -> MetadataAccessorFunction? {
        let fieldAddress = try context.addressFromOffset(offset + layout.offset(of: .accessFunctionPtr))
        let relativeOffset: Int32 = try context.readElement(at: fieldAddress)
        let targetAddress = context.advanceAddress(fieldAddress, by: Int(relativeOffset))
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
    public func typeImportInfo<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> TypeImportInfo? {
        guard hasImportInfo else { return nil }
        return try typeImportInfo(in: MachOContext(machO))
    }

    /// In-process variant of ``typeImportInfo(in:)-swift.method``.
    public func typeImportInfo() throws -> TypeImportInfo? {
        guard hasImportInfo else { return nil }
        let nameFieldPointer = try layout.pointer(from: asPointer, of: .name)
        var cursor = try layout.name.resolveDirectOffset(from: nameFieldPointer)
        var components: [String] = []
        // The first string is the user-facing name the descriptor's `name`
        // already vends; the components follow it, and an empty string ends
        // the sequence.
        var current = String(cString: cursor.assumingMemoryBound(to: CChar.self))
        while true {
            cursor = cursor.advanced(by: current.utf8.count + 1)
            current = String(cString: cursor.assumingMemoryBound(to: CChar.self))
            if current.isEmpty { break }
            components.append(current)
        }
        return TypeImportInfo(components: components)
    }

    /// `ReadingContext` variant of ``typeImportInfo(in:)-swift.method``.
    public func typeImportInfo<Context: ReadingContext>(in context: Context) throws -> TypeImportInfo? {
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
