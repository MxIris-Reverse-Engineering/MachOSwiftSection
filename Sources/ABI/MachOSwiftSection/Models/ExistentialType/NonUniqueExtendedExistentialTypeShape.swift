import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct NonUniqueExtendedExistentialTypeShape {
    public struct Layout: LayoutProtocol {
        public let uniqueCache: RelativeDirectPointer<Pointer<ExtendedExistentialTypeShape>>
        public let localCopy: ExtendedExistentialTypeShape.Layout
    }
}

// MARK: - ReadingContext Support

extension NonUniqueExtendedExistentialTypeShape {
    public func existentialType(in context: some ReadingContext) throws -> MangledName {
        let baseAddress = try context.addressFromOffset(offset(of: \.localCopy.existentialType))
        return try layout.localCopy.existentialType.resolve(at: baseAddress, in: context)
    }
}
