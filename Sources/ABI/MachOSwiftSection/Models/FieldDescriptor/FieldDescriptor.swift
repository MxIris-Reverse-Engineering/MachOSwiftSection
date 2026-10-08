import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct FieldDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let mangledTypeName: RelativeDirectPointer<MangledName>
        public let superclass: RelativeOffset
        public let kind: UInt16
        public let fieldRecordSize: UInt16
        public let numFields: UInt32
    }
}

extension FieldDescriptor {
    public var kind: FieldDescriptorKind { .init(rawValue: layout.kind)! }
}

// MARK: - ReadingContext Support

extension FieldDescriptor {
    public func mangledTypeName(in context: some ReadingContext) throws -> MangledName {
        return try layout.mangledTypeName.resolve(at: try context.addressFromOffset(offset(of: \.mangledTypeName)), in: context)
    }

    public func records(in context: some ReadingContext) throws -> [FieldRecord] {
        guard layout.fieldRecordSize != 0 else { return [] }
        let offset = offset + MemoryLayout<FieldDescriptor.Layout>.size
        return try context.readWrapperElements(at: try context.addressFromOffset(offset), numberOfElements: layout.numFields.cast())
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension FieldDescriptor {
    @available(*, deprecated, message: "Pass a ReadingContext: mangledTypeName(in: machO.context).")
    public func mangledTypeName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName {
        try mangledTypeName(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: records(in: machO.context).")
    public func records(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> [FieldRecord] {
        try records(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: mangledTypeName(in: .inProcess).")
    public func mangledTypeName() throws -> MangledName {
        try mangledTypeName(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: records(in: .inProcess).")
    public func records() throws -> [FieldRecord] {
        try records(in: InProcessContext.shared)
    }
}
