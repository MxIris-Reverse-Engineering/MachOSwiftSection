import Foundation
import MachOFoundation
import MachOMacro

@Layout
public protocol MetatypeMetadataLayout: MetadataLayout {
    var instanceType: ConstMetadataPointer<Metadata> { get }
}












