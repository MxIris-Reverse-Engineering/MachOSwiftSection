import Foundation
import MachOMacro
import MachOFoundation

@Layout
public protocol MetadataLayout: LayoutProtocol {
    var kind: StoredPointer { get }
}
