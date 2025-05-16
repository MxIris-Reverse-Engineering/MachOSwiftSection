import Foundation

extension Bool: @retroactive RawRepresentable {
    public var rawValue: UInt8 { self ? 1 : 0 }
    public init?(rawValue: UInt8) {
        self = rawValue != 0
    }
}
