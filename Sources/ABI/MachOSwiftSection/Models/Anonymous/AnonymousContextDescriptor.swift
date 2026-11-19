import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct AnonymousContextDescriptor: AnonymousContextDescriptorProtocol {
    public struct Layout: AnonymousContextDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeContextPointer
    }
}
