import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct AssociatedTypeRecord: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let name: RelativeDirectPointer<String>
        public let substitutedTypeName: RelativeDirectPointer<MangledName>
    }
}

extension AssociatedTypeRecord {
    public func name(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> String {
        return try layout.name.resolve(from: offset(of: \.name), in: machO)
    }

    public func substitutedTypeName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName {
        return try layout.substitutedTypeName.resolve(from: offset(of: \.substitutedTypeName), in: machO)
    }
}

extension AssociatedTypeRecord {
    public func name() throws -> String {
        return try layout.name.resolve(from: pointer(of: \.name))
    }

    public func substitutedTypeName() throws -> MangledName {
        return try layout.substitutedTypeName.resolve(from: pointer(of: \.substitutedTypeName))
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
