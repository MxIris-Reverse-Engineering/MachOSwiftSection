import Foundation
import MachOSwiftSectionMacro

@Layout
public protocol MetadataBoundsLayout {
    var negativeSizeInWords: UInt32 { get }
    var positiveSizeInWords: UInt32 { get }
}
