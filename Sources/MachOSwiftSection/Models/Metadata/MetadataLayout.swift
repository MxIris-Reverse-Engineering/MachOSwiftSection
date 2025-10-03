import Foundation

import MachOFoundation

@Layout
public protocol MetadataLayout: LayoutProtocol {
    var kind: StoredPointer { get }
}
