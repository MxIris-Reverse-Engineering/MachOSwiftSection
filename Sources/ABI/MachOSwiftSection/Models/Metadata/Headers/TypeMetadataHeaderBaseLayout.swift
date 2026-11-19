import Foundation
import MachOKit
import MachOBase
import Utilities

@Layout
public protocol TypeMetadataHeaderBaseLayout: LayoutProtocol {
    var valueWitnesses: Pointer<ValueWitnessTable> { get }
}
