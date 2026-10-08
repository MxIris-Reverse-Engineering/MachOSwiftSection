import Foundation
import MachOBase

@LocatableLayoutWrapping
public struct GenericValueDescriptor: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let type: UInt32
    }
}

extension GenericValueDescriptor {
    public var type: GenericValueType {
        .init(rawValue: layout.type)!
    }
}
