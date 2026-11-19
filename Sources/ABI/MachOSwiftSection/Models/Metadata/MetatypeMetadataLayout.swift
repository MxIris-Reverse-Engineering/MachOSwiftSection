import Foundation
import MachOBase
import Utilities

@Layout
public protocol MetatypeMetadataLayout: MetadataLayout {
    var instanceType: ConstMetadataPointer<Metadata> { get }
}
