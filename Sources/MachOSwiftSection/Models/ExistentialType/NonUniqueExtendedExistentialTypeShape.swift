import Foundation
import MachOKit
import MachOFoundation

public struct NonUniqueExtendedExistentialTypeShape: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let uniqueCache: RelativeDirectPointer<Pointer<ExtendedExistentialTypeShape>>
        public let localCopy: ExtendedExistentialTypeShape.Layout
    }

    public var layout: Layout

    public let offset: Int

    public init(layout: Layout, offset: Int) {
        self.layout = layout
        self.offset = offset
    }
}

extension NonUniqueExtendedExistentialTypeShape {
    public func existentialType<MachO: MachOSwiftSectionRepresentableWithCache>(in machO: MachO) throws -> MangledName {
        try layout.localCopy.existentialType.resolve(from: offset(of: \.localCopy.existentialType), in: machO)
    }
}


extension NonUniqueExtendedExistentialTypeShape {
    public func existentialType() throws -> MangledName {
        try layout.localCopy.existentialType.resolve(from: pointer(of: \.localCopy.existentialType))
    }
}
