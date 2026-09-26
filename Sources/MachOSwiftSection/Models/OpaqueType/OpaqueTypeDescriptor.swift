import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct OpaqueTypeDescriptor: OpaqueTypeDescriptorProtocol {
    public struct Layout: OpaqueTypeDescriptorLayout {
        public let flags: ContextDescriptorFlags
        public let parent: RelativeContextPointer
    }
}
