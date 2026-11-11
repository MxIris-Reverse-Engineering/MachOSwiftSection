import Foundation
import MachOKit
import MachOBase

public struct BuiltinType: TopLevelType {
    public let descriptor: BuiltinTypeDescriptor

    public let typeName: MangledName?
}

// MARK: - ReadingContext Support

extension BuiltinType {
    public init(descriptor: BuiltinTypeDescriptor, in context: some ReadingContext) throws {
        self.descriptor = descriptor
        self.typeName = try descriptor.typeName(in: context)
    }
}
