import Foundation
import MachOBase

@LocatableLayoutWrapping
public struct GenericWitnessTable: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let witnessTableSizeInWords: UInt16
        public let witnessTablePrivateSizeInWordsAndRequiresInstantiation: UInt16
        public let instantiator: RelativeDirectRawPointer
        public let privateData: RelativeDirectRawPointer
    }
}
