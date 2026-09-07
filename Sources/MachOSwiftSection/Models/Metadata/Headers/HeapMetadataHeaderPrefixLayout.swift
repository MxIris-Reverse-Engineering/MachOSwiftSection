import Foundation
import MachOKit
import MachOBase

@Layout
public protocol HeapMetadataHeaderPrefixLayout: LayoutProtocol {
    var destroy: RawPointer { get }
}
