import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct FieldRecord {
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
