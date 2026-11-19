import Foundation
import SwiftStdlibToolbox

/// Mirrors `swift::GenericEnvironmentFlags` (`swift/ABI/MetadataValues.h`).
public struct GenericEnvironmentFlags: OptionSet, Sendable {
    public typealias RawValue = UInt32

    public let rawValue: RawValue

    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }

    @BitField(bits: 0..<12)
    public var numberOfGenericParameterLevels: RawValue

    @BitField(bits: 12..<28)
    public var numberOfGenericRequirements: RawValue
}
