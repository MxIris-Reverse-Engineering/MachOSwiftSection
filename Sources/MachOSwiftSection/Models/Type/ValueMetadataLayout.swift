import Foundation
import MachOFoundation

@Layout
public protocol ValueMetadataLayout: MetadataLayout {
    var descriptor: Pointer<ValueTypeDescriptorWrapper> { get }
}
