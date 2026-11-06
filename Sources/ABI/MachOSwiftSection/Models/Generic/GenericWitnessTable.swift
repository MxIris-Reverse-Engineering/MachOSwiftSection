import Foundation
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct GenericWitnessTable {
    public struct Layout: LayoutProtocol {
        public let witnessTableSizeInWords: UInt16
        public let witnessTablePrivateSizeInWordsAndRequiresInstantiation: UInt16
        public let instantiator: RelativeDirectRawPointer
        public let privateData: RelativeDirectRawPointer
    }
}
