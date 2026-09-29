import Foundation
import MachOBase

@LocatableLayoutWrapping
public struct ResilientWitnessesHeader: ResolvableLocatableLayoutWrapper {
    public struct Layout: LayoutProtocol {
        public let numWitnesses: UInt32
    }
}
