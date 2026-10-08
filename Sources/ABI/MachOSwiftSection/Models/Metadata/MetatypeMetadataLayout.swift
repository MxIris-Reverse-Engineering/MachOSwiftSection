import Foundation
import MachOBase

@Layout
public protocol MetatypeMetadataLayout: MetadataLayout {
    var instanceType: ConstMetadataPointer<Metadata> { get }
}
