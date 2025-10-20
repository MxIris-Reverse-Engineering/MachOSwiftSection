import Foundation
import MachOKit
import MachOFoundation


@Layout
public protocol HeapMetadataHeaderPrefixLayout: LayoutProtocol {
    var destroy: RawPointer { get }
}
