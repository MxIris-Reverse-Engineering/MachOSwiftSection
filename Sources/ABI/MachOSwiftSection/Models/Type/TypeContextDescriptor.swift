import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct TypeContextDescriptor: TypeContextDescriptorProtocol {
    public struct Layout: TypeContextDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeContextPointer
        public let name: RelativeDirectPointer<String>
        public let accessFunctionPtr: RelativeDirectPointer<MetadataAccessorFunction>
        public let fieldDescriptor: RelativeDirectPointer<FieldDescriptor>
    }
}

// MARK: - ReadingContext Support

extension TypeContextDescriptor {
    public func enumDescriptor(in context: some ReadingContext) throws -> EnumDescriptor? {
        guard layout.flags.kind == .enum else { return nil }
        return try context.readWrapperElement(at: try context.addressFromOffset(offset)) as EnumDescriptor
    }

    public func structDescriptor(in context: some ReadingContext) throws -> StructDescriptor? {
        guard layout.flags.kind == .struct else { return nil }
        return try context.readWrapperElement(at: try context.addressFromOffset(offset)) as StructDescriptor
    }

    public func classDescriptor(in context: some ReadingContext) throws -> ClassDescriptor? {
        guard layout.flags.kind == .class else { return nil }
        return try context.readWrapperElement(at: try context.addressFromOffset(offset)) as ClassDescriptor
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension TypeContextDescriptor {
    @available(*, deprecated, message: "Pass a ReadingContext: enumDescriptor(in: machO.context).")
    public func enumDescriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> EnumDescriptor? {
        try enumDescriptor(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: structDescriptor(in: machO.context).")
    public func structDescriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> StructDescriptor? {
        try structDescriptor(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: classDescriptor(in: machO.context).")
    public func classDescriptor(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> ClassDescriptor? {
        try classDescriptor(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: enumDescriptor(in: .inProcess).")
    public func enumDescriptor() throws -> EnumDescriptor? {
        try enumDescriptor(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: structDescriptor(in: .inProcess).")
    public func structDescriptor() throws -> StructDescriptor? {
        try structDescriptor(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: classDescriptor(in: .inProcess).")
    public func classDescriptor() throws -> ClassDescriptor? {
        try classDescriptor(in: InProcessContext.shared)
    }
}
