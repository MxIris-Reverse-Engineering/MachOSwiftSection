import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct TypeMetadataLayoutPrefix: TypeMetadataLayoutPrefixProtocol {
    public struct Layout: TypeMetadataLayoutPrefixLayout {
        public let layoutString: Pointer<String?>
    }
}
