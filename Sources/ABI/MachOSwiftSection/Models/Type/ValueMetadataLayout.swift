import Foundation
import MachOBase
import Utilities

@Layout
public protocol ValueMetadataLayout: MetadataLayout {
    var descriptor: Pointer<ValueTypeDescriptorWrapper> { get }
}
