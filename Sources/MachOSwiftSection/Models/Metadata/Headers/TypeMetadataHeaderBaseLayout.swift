import Foundation
import MachOKit
import MachOBase

@Layout
public protocol TypeMetadataHeaderBaseLayout: LayoutProtocol {
    var valueWitnesses: Pointer<ValueWitnessTable> { get }
}
