import Foundation
import SwiftStdlibToolbox

public struct AnonymousContextDescriptorFlags: FlagSet {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    @BitField(bits: 0)
    public var hasMangledName: Bool
}
