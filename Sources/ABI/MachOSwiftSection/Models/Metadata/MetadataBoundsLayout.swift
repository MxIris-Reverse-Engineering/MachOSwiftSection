import Foundation
import MachOBase
import Utilities

@Layout
public protocol MetadataBoundsLayout: LayoutProtocol {
    var negativeSizeInWords: UInt32 { get }
    var positiveSizeInWords: UInt32 { get }

    init(negativeSizeInWords: UInt32, positiveSizeInWords: UInt32)
}
