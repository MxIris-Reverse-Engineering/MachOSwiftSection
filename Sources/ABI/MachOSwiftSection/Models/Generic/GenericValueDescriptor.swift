import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct GenericValueDescriptor {
    public struct Layout: LayoutProtocol {
        public let type: UInt32
    }
}

extension GenericValueDescriptor {
    public var type: GenericValueType {
        .init(rawValue: layout.type)!
    }
}
