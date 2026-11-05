import Foundation
import SwiftStdlibToolbox

public struct ExtraClassDescriptorFlags: FlagSet {
    public typealias RawValue = UInt32

    public let rawValue: RawValue

    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }

    @BitField(bits: 0)
    public var hasObjCResilientClassStub: Bool
}
