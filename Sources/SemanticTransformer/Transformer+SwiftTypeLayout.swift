import Foundation

// MARK: - Swift Type Layout Comment Transformer Module

extension Transformer {
    /// Customizes Swift type layout comment format using token templates.
    ///
    /// Available tokens:
    /// - `${size}` - Type size in bytes
    /// - `${stride}` - Type stride in bytes
    /// - `${alignment}` - Type alignment
    /// - `${extraInhabitantCount}` - Extra inhabitant count
    /// - `${isPOD}` - Whether the type is plain old data
    /// - `${isInlineStorage}` - Whether the type uses inline storage
    /// - `${isBitwiseTakable}` - Whether the type is bitwise takable
    /// - `${isBitwiseBorrowable}` - Whether the type is bitwise borrowable
    /// - `${isCopyable}` - Whether the type is copyable
    /// - `${hasEnumWitnesses}` - Whether the type has enum witnesses
    /// - `${isIncomplete}` - Whether the type layout is incomplete
    ///
    /// Flags the caller cannot know (the static, offline layout path knows
    /// bitwise-takability but none of the value-witness-flag bits) render as
    /// `"unknown"` — honest, and invisible in templates that do not reference
    /// them.
    public struct SwiftTypeLayout: Module {
        public typealias Parameter = Token
        public typealias Output = String

        public static let displayName = "Type Layout Comment"

        public var isEnabled: Bool

        public var template: String

        public var useHexadecimal: Bool

        public init(isEnabled: Bool = false, template: String = Templates.standard, useHexadecimal: Bool = false) {
            self.isEnabled = isEnabled
            self.template = template
            self.useHexadecimal = useHexadecimal
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
            self.template = try container.decodeIfPresent(String.self, forKey: .template) ?? Templates.standard
            self.useHexadecimal = try container.decodeIfPresent(Bool.self, forKey: .useHexadecimal) ?? false
        }

        /// Renders the template with actual type layout values.
        public func transform(_ input: Input) -> String {
            var rendered = template
            rendered = rendered.replacingOccurrences(of: Token.size.placeholder, with: formatNumeric(input.size))
            rendered = rendered.replacingOccurrences(of: Token.stride.placeholder, with: formatNumeric(input.stride))
            rendered = rendered.replacingOccurrences(of: Token.alignment.placeholder, with: formatNumeric(input.alignment))
            rendered = rendered.replacingOccurrences(of: Token.extraInhabitantCount.placeholder, with: formatNumeric(input.extraInhabitantCount))
            rendered = rendered.replacingOccurrences(of: Token.isPOD.placeholder, with: formatFlag(input.isPOD))
            rendered = rendered.replacingOccurrences(of: Token.isInlineStorage.placeholder, with: formatFlag(input.isInlineStorage))
            rendered = rendered.replacingOccurrences(of: Token.isBitwiseTakable.placeholder, with: formatFlag(input.isBitwiseTakable))
            rendered = rendered.replacingOccurrences(of: Token.isBitwiseBorrowable.placeholder, with: formatFlag(input.isBitwiseBorrowable))
            rendered = rendered.replacingOccurrences(of: Token.isCopyable.placeholder, with: formatFlag(input.isCopyable))
            rendered = rendered.replacingOccurrences(of: Token.hasEnumWitnesses.placeholder, with: formatFlag(input.hasEnumWitnesses))
            rendered = rendered.replacingOccurrences(of: Token.isIncomplete.placeholder, with: formatFlag(input.isIncomplete))
            return rendered
        }

        private func formatNumeric(_ value: Int) -> String {
            useHexadecimal ? "0x\(String(value, radix: 16, uppercase: true))" : String(value)
        }

        private func formatFlag(_ value: Bool?) -> String {
            value.map(String.init) ?? "unknown"
        }

        /// Checks if the template contains a specific token.
        public func contains(_ token: Token) -> Bool {
            template.contains(token.placeholder)
        }
    }
}

// MARK: - Input

extension Transformer.SwiftTypeLayout {
    /// Input for type layout transformation. Value-witness-flag fields are
    /// optional: a caller that cannot know one (the static, offline layout
    /// path) passes `nil` and the token renders as `"unknown"`.
    public struct Input: Sendable {
        public let size: Int
        public let stride: Int
        public let alignment: Int
        public let extraInhabitantCount: Int
        public let isPOD: Bool?
        public let isInlineStorage: Bool?
        public let isBitwiseTakable: Bool?
        public let isBitwiseBorrowable: Bool?
        public let isCopyable: Bool?
        public let hasEnumWitnesses: Bool?
        public let isIncomplete: Bool?

        public init(
            size: Int,
            stride: Int,
            alignment: Int,
            extraInhabitantCount: Int,
            isPOD: Bool? = nil,
            isInlineStorage: Bool? = nil,
            isBitwiseTakable: Bool? = nil,
            isBitwiseBorrowable: Bool? = nil,
            isCopyable: Bool? = nil,
            hasEnumWitnesses: Bool? = nil,
            isIncomplete: Bool? = nil
        ) {
            self.size = size
            self.stride = stride
            self.alignment = alignment
            self.extraInhabitantCount = extraInhabitantCount
            self.isPOD = isPOD
            self.isInlineStorage = isInlineStorage
            self.isBitwiseTakable = isBitwiseTakable
            self.isBitwiseBorrowable = isBitwiseBorrowable
            self.isCopyable = isCopyable
            self.hasEnumWitnesses = hasEnumWitnesses
            self.isIncomplete = isIncomplete
        }
    }
}

// MARK: - Token

extension Transformer.SwiftTypeLayout {
    /// Available tokens for type layout templates.
    public enum Token: String, CaseIterable, Sendable {
        case size
        case stride
        case alignment
        case extraInhabitantCount
        case isPOD
        case isInlineStorage
        case isBitwiseTakable
        case isBitwiseBorrowable
        case isCopyable
        case hasEnumWitnesses
        case isIncomplete

        public var placeholder: String { "${\(rawValue)}" }
        public var displayName: String {
            switch self {
            case .size: "Size"
            case .stride: "Stride"
            case .alignment: "Alignment"
            case .extraInhabitantCount: "Extra Inhabitant Count"
            case .isPOD: "Is POD"
            case .isInlineStorage: "Is Inline Storage"
            case .isBitwiseTakable: "Is Bitwise Takable"
            case .isBitwiseBorrowable: "Is Bitwise Borrowable"
            case .isCopyable: "Is Copyable"
            case .hasEnumWitnesses: "Has Enum Witnesses"
            case .isIncomplete: "Is Incomplete"
            }
        }
    }
}

// MARK: - Templates

extension Transformer.SwiftTypeLayout {
    public enum Templates {
        /// Default style matching non-transformed output:
        /// "Type Layout: (size: 8, stride: 8, alignment: 8, extraInhabitantCount: 0)"
        public static let standard = "Type Layout: (size: ${size}, stride: ${stride}, alignment: ${alignment}, extraInhabitantCount: ${extraInhabitantCount})"

        /// Verbose style includes flags:
        /// "Type Layout: (size: 8, stride: 8, alignment: 8, extraInhabitantCount: 0, isPOD: true, ...)"
        public static let verbose = "Type Layout: (size: ${size}, stride: ${stride}, alignment: ${alignment}, extraInhabitantCount: ${extraInhabitantCount}, isPOD: ${isPOD}, isInlineStorage: ${isInlineStorage}, isBitwiseTakable: ${isBitwiseTakable}, isBitwiseBorrowable: ${isBitwiseBorrowable}, isCopyable: ${isCopyable}, hasEnumWitnesses: ${hasEnumWitnesses}, isIncomplete: ${isIncomplete})"

        /// Compact style: "size: 8, stride: 8, align: 8"
        public static let compact = "size: ${size}, stride: ${stride}, align: ${alignment}"

        /// Size only: "8 bytes"
        public static let sizeOnly = "${size} bytes"

        /// Tuple element style matching non-transformed tuple output:
        /// "Layout: (size: 8, stride: 8, alignment: 8, extraInhabitantCount: 0)"
        public static let tupleElement = "Layout: (size: ${size}, stride: ${stride}, alignment: ${alignment}, extraInhabitantCount: ${extraInhabitantCount})"

        public static let all: [(name: String, template: String)] = [
            ("Standard", standard),
            ("Verbose", verbose),
            ("Compact", compact),
            ("Size Only", sizeOnly),
            ("Tuple Element", tupleElement),
        ]
    }
}
