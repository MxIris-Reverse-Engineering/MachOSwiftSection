import Foundation
import MachOMacro

@Layout
public protocol MetadataBoundsLayout {
    var negativeSizeInWords: UInt32 { get }
    var positiveSizeInWords: UInt32 { get }
}
