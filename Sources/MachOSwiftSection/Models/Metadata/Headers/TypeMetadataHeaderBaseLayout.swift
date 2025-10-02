import Foundation
import MachOKit
import MachOFoundation
import MachOMacro

@Layout
public protocol TypeMetadataHeaderBaseLayout: LayoutProtocol {
    var valueWitnesses: Pointer<ValueWitnessTable> { get }
}
