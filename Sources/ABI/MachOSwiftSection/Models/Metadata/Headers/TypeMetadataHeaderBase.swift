import Foundation
import MachOKit
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct TypeMetadataHeaderBase: TypeMetadataHeaderBaseProtocol {
    public struct Layout: TypeMetadataHeaderBaseLayout {
        public let valueWitnesses: Pointer<ValueWitnessTable>
    }
}
