import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct TypeMetadataHeader: TypeMetadataHeaderProtocol {
    public struct Layout: TypeMetadataHeaderLayout {
        public let layoutString: Pointer<String?>
        public let valueWitnesses: Pointer<ValueWitnessTable>
    }
}
