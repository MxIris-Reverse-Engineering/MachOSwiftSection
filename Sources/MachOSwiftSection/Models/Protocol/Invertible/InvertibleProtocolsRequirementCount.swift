import Foundation

public struct InvertibleProtocolsRequirementCount: RawRepresentable {
    public let rawValue: UInt16
    
    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }
}
