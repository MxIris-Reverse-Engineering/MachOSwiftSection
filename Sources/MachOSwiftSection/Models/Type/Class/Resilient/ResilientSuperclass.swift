import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct ResilientSuperclass: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let superclass: RelativeDirectRawPointer
    }
}
