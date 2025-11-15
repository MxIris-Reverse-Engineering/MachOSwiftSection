import Foundation
import MachOKit
import MachOFoundation

@Layout
public protocol StructMetadataLayout: MetadataLayout {
    var descriptor: Pointer<StructDescriptor> { get }
}
