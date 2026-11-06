import Foundation
import MachOBase

@ResolvableLocatableLayoutWrapper
public struct ResilientWitnessesHeader {
    public struct Layout: LayoutProtocol {
        public let numWitnesses: UInt32
    }
}
