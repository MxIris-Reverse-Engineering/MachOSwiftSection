import Foundation

public struct AnonymousContextDescriptorFlags: FlagSet {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    private enum Bits {
        static let hasMangledName = 0
    }

    public var hasMangledName: Bool {
        flag(bit: Bits.hasMangledName)
    }
}
