import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct AssociatedTypeRecord {
    public struct Layout: LayoutProtocol {
        public let name: RelativeDirectPointer<String>
        public let substitutedTypeName: RelativeDirectPointer<MangledName>
    }
}

// MARK: - ReadingContext Support

extension AssociatedTypeRecord {
    public func name(in context: some ReadingContext) throws -> String {
        return try layout.name.resolve(at: try context.addressFromOffset(offset(of: \.name)), in: context)
    }

    public func substitutedTypeName(in context: some ReadingContext) throws -> MangledName {
        return try layout.substitutedTypeName.resolve(at: try context.addressFromOffset(offset(of: \.substitutedTypeName)), in: context)
    }
}
