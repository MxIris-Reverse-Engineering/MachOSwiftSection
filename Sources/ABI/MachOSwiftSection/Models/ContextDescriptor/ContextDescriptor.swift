import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct ContextDescriptor: ContextDescriptorProtocol {
    public struct Layout: ContextDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeContextPointer
    }
}
