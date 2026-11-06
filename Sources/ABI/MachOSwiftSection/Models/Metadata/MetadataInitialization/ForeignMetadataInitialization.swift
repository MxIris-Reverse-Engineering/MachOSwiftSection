import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct ForeignMetadataInitialization {
    public struct Layout: LayoutProtocol {
        public let completionFunction: RelativeDirectRawPointer
    }
}
