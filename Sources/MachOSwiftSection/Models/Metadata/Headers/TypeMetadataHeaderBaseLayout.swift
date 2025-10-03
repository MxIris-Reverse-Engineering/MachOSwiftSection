import Foundation
import MachOKit
import MachOFoundation


@Layout
public protocol TypeMetadataHeaderBaseLayout: LayoutProtocol {
    var valueWitnesses: Pointer<ValueWitnessTable> { get }
}
