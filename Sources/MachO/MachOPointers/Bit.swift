/// A single-bit value extracted from a relative pointer int pair.
///
/// Used as the `Value` generic parameter for `TargetRelativeIndirectablePointerIntPair`
/// instead of `Bool`, avoiding the need for a retroactive `Bool: RawRepresentable`
/// conformance that can fail to register in code injection contexts.
public struct Bit: RawRepresentable, Sendable, Equatable, Hashable {
    public let rawValue: UInt8

    public init?(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public var boolValue: Bool {
        rawValue != 0
    }
}
