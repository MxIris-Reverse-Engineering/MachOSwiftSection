import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct AnyClassMetadata: AnyClassMetadataProtocol {
    public struct Layout: AnyClassMetadataLayout {
        public let kind: StoredPointer
        public let superclass: Pointer<AnyClassMetadata?>
    }
}
