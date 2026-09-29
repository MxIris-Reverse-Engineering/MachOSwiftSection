import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct ModuleContextDescriptor: ModuleContextDescriptorProtocol {
    public struct Layout: ModuleContextDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeContextPointer
        public let name: RelativeDirectPointer<String>
    }
}
