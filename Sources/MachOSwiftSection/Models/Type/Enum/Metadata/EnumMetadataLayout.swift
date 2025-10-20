import Foundation
import MachOFoundation


@Layout
public protocol EnumMetadataLayout: MetadataLayout {
    var descriptor: Pointer<EnumDescriptor> { get }
}
