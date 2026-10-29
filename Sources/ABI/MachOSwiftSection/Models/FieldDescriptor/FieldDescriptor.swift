import Foundation
import MachOKit
import MachOBase

/// A record in `__swift5_fieldmd`: a nominal type's or protocol's name, and
/// one trailing ``FieldRecord`` per stored property or enum case. The section
/// is a sequence of them, walked by size.
@LocatableLayoutWrapping
public struct FieldDescriptor: TopLevelDescriptor {
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

    /// Total length in bytes of the descriptor including its trailing
    /// records, which is how the section walk advances to the next one.
    public var actualSize: Int {
        MemoryLayout<Layout>.size + Int(layout.numFields) * Int(layout.fieldRecordSize)
    }
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
