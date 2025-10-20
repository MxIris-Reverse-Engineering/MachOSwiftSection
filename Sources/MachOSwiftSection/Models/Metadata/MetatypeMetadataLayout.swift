import Foundation
import MachOFoundation


@Layout
public protocol MetatypeMetadataLayout: MetadataLayout {
    var instanceType: ConstMetadataPointer<Metadata> { get }
}












