import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct NonUniqueExtendedExistentialTypeShape: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let uniqueCache: RelativeDirectPointer<Pointer<ExtendedExistentialTypeShape>>
        public let localCopy: ExtendedExistentialTypeShape.Layout
    }
}

extension NonUniqueExtendedExistentialTypeShape {
    public func existentialType(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName {
        try layout.localCopy.existentialType.resolve(from: offset(of: \.localCopy.existentialType), in: machO)
    }
}


extension NonUniqueExtendedExistentialTypeShape {
    public func existentialType() throws -> MangledName {
        try layout.localCopy.existentialType.resolve(from: pointer(of: \.localCopy.existentialType))
    }
}

// MARK: - ReadingContext Support

extension NonUniqueExtendedExistentialTypeShape {
    public func existentialType(in context: some ReadingContext) throws -> MangledName {
        let baseAddress = try context.addressFromOffset(offset(of: \.localCopy.existentialType))
        return try layout.localCopy.existentialType.resolve(at: baseAddress, in: context)
    }
}
