import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct ResilientSuperclass {
    public struct Layout: LayoutProtocol {
        public let superclass: RelativeDirectRawPointer
    }
}
