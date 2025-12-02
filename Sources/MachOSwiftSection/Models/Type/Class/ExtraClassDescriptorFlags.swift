import Foundation

public struct ExtraClassDescriptorFlags: FlagSet {
    public typealias RawValue = UInt32

    public let rawValue: RawValue

    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }

    private enum Bits {
        static let hasObjCResilientClassStub = 0
    }

    public var hasObjCResilientClassStub: Bool {
        flag(bit: Bits.hasObjCResilientClassStub)
    }
}
