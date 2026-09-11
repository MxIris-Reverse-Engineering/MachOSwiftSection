import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct ContextDescriptor: ContextDescriptorProtocol {
    public struct Layout: ContextDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeContextPointer
    }
}
