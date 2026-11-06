import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct OpaqueTypeDescriptor: OpaqueTypeDescriptorProtocol {
    public struct Layout: OpaqueTypeDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeContextPointer
    }
}
