import Foundation
import MachOKit
import MachOBase
import Utilities

@Layout
public protocol HeapMetadataHeaderPrefixLayout: LayoutProtocol {
    var destroy: RawPointer { get }
}
