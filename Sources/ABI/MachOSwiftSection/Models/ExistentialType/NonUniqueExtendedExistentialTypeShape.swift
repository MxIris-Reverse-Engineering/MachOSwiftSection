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

// MARK: - ReadingContext Support

extension NonUniqueExtendedExistentialTypeShape {
    public func existentialType(in context: some ReadingContext) throws -> MangledName {
        let baseAddress = try context.addressFromOffset(offset(of: \.localCopy.existentialType))
        return try layout.localCopy.existentialType.resolve(at: baseAddress, in: context)
    }
}

// MARK: - Deprecated Mach-O and pointer forms

extension NonUniqueExtendedExistentialTypeShape {
    @available(*, deprecated, message: "Pass a ReadingContext: existentialType(in: machO.context).")
    public func existentialType(in machO: some MachOSwiftSectionRepresentableWithCache) throws -> MangledName {
        try existentialType(in: machO.context)
    }

    @available(*, deprecated, message: "Pass a ReadingContext: existentialType(in: .inProcess).")
    public func existentialType() throws -> MangledName {
        try existentialType(in: InProcessContext.shared)
    }
}
