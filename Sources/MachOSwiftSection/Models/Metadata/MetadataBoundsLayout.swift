import Foundation

import MachOFoundation

@Layout
public protocol MetadataBoundsLayout: LayoutProtocol {
    var negativeSizeInWords: UInt32 { get }
    var positiveSizeInWords: UInt32 { get }
}
