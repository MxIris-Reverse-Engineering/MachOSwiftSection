import Foundation
import MachOFoundation
import MachOMacro

@Layout
public protocol EnumMetadataLayout: MetadataLayout {
    var descriptor: Pointer<EnumDescriptor> { get }
}
