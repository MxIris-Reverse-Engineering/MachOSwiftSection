import Foundation
import MachOBase

@Layout
public protocol ValueMetadataLayout: MetadataLayout {
    var descriptor: Pointer<ValueTypeDescriptorWrapper> { get }
}
