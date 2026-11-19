import Foundation
import MachOBase
import Utilities

@Layout
public protocol MetadataLayout: LayoutProtocol {
    var kind: StoredPointer { get }
}
