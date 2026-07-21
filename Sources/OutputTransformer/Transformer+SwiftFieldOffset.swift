import Foundation

// MARK: - Swift Field Offset Transformer Module

extension Transformer {
    /// Customizes Swift field offset comment format using token templates.
    ///
    /// Available tokens:
    /// - `${startOffset}` - Field start offset
    /// - `${endOffset}` - Field end offset
    ///
    /// Example:
    /// ```swift
    /// var module = Transformer.SwiftFieldOffset()
    /// module.isEnabled = true
    /// module.template = "${startOffset} ..< ${endOffset}"  // "0 ..< 8"
    /// module.template = "offset: ${startOffset}"           // "offset: 0"
    /// ```
    public struct SwiftFieldOffset: Module {
        public typealias Parameter = Token
        public typealias Output = String

        public static let displayName = "Swift Field Offset Comment"

        public var isEnabled: Bool

        public var template: String

        public var useHexadecimal: Bool

        public init(isEnabled: Bool = false, template: String = Templates.standard, useHexadecimal: Bool = true) {
            self.isEnabled = isEnabled
            self.template = template
            self.useHexadecimal = useHexadecimal
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
            self.template = try container.decodeIfPresent(String.self, forKey: .template) ?? Templates.standard
            self.useHexadecimal = try container.decodeIfPresent(Bool.self, forKey: .useHexadecimal) ?? true
        }

        /// Renders the template with actual offset values.
        ///
        /// When `endOffset` is `nil` (last field in a type), the `${endOffset}`
        /// token is replaced with `"?"`.
        public func transform(_ input: Input) -> String {
            template
                .replacingOccurrences(of: Token.startOffset.placeholder, with: formatValue(input.startOffset))
                .replacingOccurrences(of: Token.endOffset.placeholder, with: input.endOffset.map(formatValue) ?? "?")
        }

        private func formatValue(_ value: Int) -> String {
            useHexadecimal ? "0x\(String(value, radix: 16, uppercase: true))" : String(value)
        }

        /// Checks if the template contains a specific token.
        public func contains(_ token: Token) -> Bool {
            template.contains(token.placeholder)
        }
    }
}

// MARK: - Input

extension Transformer.SwiftFieldOffset {
    /// Input for field offset transformation.
    public struct Input: Sendable {
        public let startOffset: Int
        public let endOffset: Int?

        public init(startOffset: Int, endOffset: Int?) {
            self.startOffset = startOffset
            self.endOffset = endOffset
        }
    }
}

// MARK: - Token

extension Transformer.SwiftFieldOffset {
    /// Available tokens for field offset templates.
    public enum Token: String, CaseIterable, Sendable {
        case startOffset
        case endOffset

        public var placeholder: String { "${\(rawValue)}" }
        public var displayName: String {
            switch self {
            case .startOffset: "Start Offset"
            case .endOffset: "End Offset"
            }
        }
    }
}

// MARK: - Templates

extension Transformer.SwiftFieldOffset {
    public enum Templates {
        /// Default style matching non-transformed output: "Field Offset: 0x0"
        public static let standard = "Field Offset: ${startOffset}"

        /// Range style: "0 ..< 8"
        public static let range = "${startOffset} ..< ${endOffset}"

        /// Labeled style: "offset: 0"
        public static let labeled = "offset: ${startOffset}"

        /// Interval style: "[0, 8)"
        public static let interval = "[${startOffset}, ${endOffset})"

        /// Start only: "0"
        public static let startOnly = "${startOffset}"

        public static let all: [(name: String, template: String)] = [
            ("Standard", standard),
            ("Range", range),
            ("Labeled", labeled),
            ("Interval", interval),
            ("Start Only", startOnly),
        ]
    }
}
