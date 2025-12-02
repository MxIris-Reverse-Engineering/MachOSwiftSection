import Foundation
import MachOKit
import MachOFoundation

public struct FieldRecord: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let flags: FieldRecordFlags
        public let mangledTypeName: RelativeDirectPointer<MangledName>
        public let fieldName: RelativeDirectPointer<String>
    }

    public let offset: Int

    public var layout: Layout

    public init(layout: Layout, offset: Int) {
        self.offset = offset
        self.layout = layout
    }
}

extension FieldRecord {
    public func mangledTypeName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> MangledName {
        return try layout.mangledTypeName.resolve(from: offset(of: \.mangledTypeName), in: machO)
    }

    public func fieldName<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> String {
        return try layout.fieldName.resolve(from: offset(of: \.fieldName), in: machO)
    }
}
