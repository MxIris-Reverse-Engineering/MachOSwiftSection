import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct FieldRecord: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let flags: FieldRecordFlags
        public let mangledTypeName: RelativeDirectPointer<MangledName>
        public let fieldName: RelativeDirectPointer<String>
    }
}

// MARK: - ReadingContext Support

extension FieldRecord {
    public func mangledTypeName(in context: some ReadingContext) throws -> MangledName {
        return try layout.mangledTypeName.resolve(at: try context.addressFromOffset(offset(of: \.mangledTypeName)), in: context)
    }

    /// The field's name, or `""` when the record carries none. A null name
    /// pointer is legal since Swift 6.4: the compiler emits no name (and no
    /// type) for an enum element that is unavailable at run time, while the
    /// element keeps its tag. Reading through the null pointer would
    /// otherwise decode the record's own bytes as the name.
    public func fieldName(in context: some ReadingContext) throws -> String {
        guard !layout.fieldName.isNull else { return "" }
        return try layout.fieldName.resolve(at: try context.addressFromOffset(offset(of: \.fieldName)), in: context)
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension FieldRecord {
    @available(*, deprecated, message: "Pass a ReadingContext: mangledTypeName(in: machO.context).")
    public func mangledTypeName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName {
        try mangledTypeName(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: fieldName(in: machO.context).")
    public func fieldName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> String {
        try fieldName(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: mangledTypeName(in: .inProcess).")
    public func mangledTypeName() throws -> MangledName {
        try mangledTypeName(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: fieldName(in: .inProcess).")
    public func fieldName() throws -> String {
        try fieldName(in: InProcessContext.shared)
    }
}
