import Foundation
import MachOKit
import MachOFoundation
import MachOMacro

@Layout
public protocol HeapMetadataHeaderPrefixLayout: LayoutProtocol {
    var destroy: RawPointer { get }
}
