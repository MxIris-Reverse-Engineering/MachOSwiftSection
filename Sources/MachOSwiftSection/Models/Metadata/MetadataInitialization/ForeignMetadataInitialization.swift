import Foundation
import MachOBase

@LocatableLayoutWrapping
public struct ForeignMetadataInitialization: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let completionFunction: RelativeDirectRawPointer
    }
}
