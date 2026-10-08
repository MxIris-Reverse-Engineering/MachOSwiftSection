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

// MARK: - ReadingContext Support

extension AssociatedTypeRecord {
    public func name(in context: some ReadingContext) throws -> String {
        return try layout.name.resolve(at: try context.addressFromOffset(offset(of: \.name)), in: context)
    }

    public func substitutedTypeName(in context: some ReadingContext) throws -> MangledName {
        return try layout.substitutedTypeName.resolve(at: try context.addressFromOffset(offset(of: \.substitutedTypeName)), in: context)
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension AssociatedTypeRecord {
    @available(*, deprecated, message: "Pass a ReadingContext: name(in: machO.context).")
    public func name(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> String {
        try name(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: substitutedTypeName(in: machO.context).")
    public func substitutedTypeName(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName {
        try substitutedTypeName(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: name(in: .inProcess).")
    public func name() throws -> String {
        try name(in: InProcessContext.shared)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: substitutedTypeName(in: .inProcess).")
    public func substitutedTypeName() throws -> MangledName {
        try substitutedTypeName(in: InProcessContext.shared)
    }
}
