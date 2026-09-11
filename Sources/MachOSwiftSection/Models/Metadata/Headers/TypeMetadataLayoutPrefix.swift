import Foundation
import MachOKit
import MachOBase

@LocatableLayoutWrapping
public struct TypeMetadataLayoutPrefix: TypeMetadataLayoutPrefixProtocol {
    public struct Layout: TypeMetadataLayoutPrefixLayout {
        public let layoutString: Pointer<String?>
    }
}
