import Foundation
public import OutputTransformer

// MARK: - Swift Configuration

extension Transformer {
    /// Configuration for the Swift-specific transformer modules.
    public struct SwiftConfiguration: Sendable, Equatable, Hashable, Codable {
        public var swiftFieldOffset: Transformer.SwiftFieldOffset
        public var swiftVTableOffset: Transformer.SwiftVTableOffset
        public var swiftMemberAddress: Transformer.SwiftMemberAddress
        public var swiftTypeLayout: Transformer.SwiftTypeLayout
        public var swiftEnumLayout: Transformer.SwiftEnumLayout

        public init(
            swiftFieldOffset: SwiftFieldOffset = .init(),
            swiftVTableOffset: SwiftVTableOffset = .init(),
            swiftMemberAddress: SwiftMemberAddress = .init(),
            swiftTypeLayout: SwiftTypeLayout = .init(),
            swiftEnumLayout: SwiftEnumLayout = .init()
        ) {
            self.swiftFieldOffset = swiftFieldOffset
            self.swiftVTableOffset = swiftVTableOffset
            self.swiftMemberAddress = swiftMemberAddress
            self.swiftTypeLayout = swiftTypeLayout
            self.swiftEnumLayout = swiftEnumLayout
        }

        // Missing-key-tolerant decoding (compatible with the previous
        // MetaCodable `@Default(ifMissing:)` persistence).
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.swiftFieldOffset = try container.decodeIfPresent(SwiftFieldOffset.self, forKey: .swiftFieldOffset) ?? .init()
            self.swiftVTableOffset = try container.decodeIfPresent(SwiftVTableOffset.self, forKey: .swiftVTableOffset) ?? .init()
            self.swiftMemberAddress = try container.decodeIfPresent(SwiftMemberAddress.self, forKey: .swiftMemberAddress) ?? .init()
            self.swiftTypeLayout = try container.decodeIfPresent(SwiftTypeLayout.self, forKey: .swiftTypeLayout) ?? .init()
            self.swiftEnumLayout = try container.decodeIfPresent(SwiftEnumLayout.self, forKey: .swiftEnumLayout) ?? .init()
        }

        /// Whether any Swift module is enabled.
        public var hasEnabledModules: Bool {
            swiftFieldOffset.isEnabled
                || swiftVTableOffset.isEnabled
                || swiftMemberAddress.isEnabled
                || swiftTypeLayout.isEnabled
                || swiftEnumLayout.isEnabled
        }
    }
}
