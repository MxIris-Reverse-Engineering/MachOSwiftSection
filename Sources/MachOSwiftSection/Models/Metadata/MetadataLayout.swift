import Foundation
import MachOBase

@Layout
public protocol MetadataLayout: LayoutProtocol {
    var kind: StoredPointer { get }
}
