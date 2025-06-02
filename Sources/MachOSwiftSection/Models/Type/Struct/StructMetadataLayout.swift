import Foundation
import MachOKit
import MachOMacro
import MachOFoundation

@Layout
public protocol StructMetadataLayout: MetadataLayout {
    var descriptor: Pointer<StructDescriptor> { get }
}
