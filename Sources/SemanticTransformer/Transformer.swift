import Foundation

// MARK: - Transformer Namespace

/// Namespace for output-transformer modules: token templates for the Swift
/// rendered-comment kinds (field offset, vtable offset, member address, type
/// layout, enum layout).
///
/// This is the library-side home of the mechanism RuntimeViewer's settings UI
/// edits — the templates, tokens, and presets all live here so every consumer
/// (the `swift-section` CLI, RuntimeViewer, direct library users) shares one
/// definition; RuntimeViewer keeps only the UI. The ObjC-side modules
/// (`CType`, `ObjCIvarOffset`) and the aggregate persistence `Configuration`
/// currently remain in RuntimeViewerCore (declared as extensions of this
/// namespace), pending a library-side home for the ObjC rendering pipeline.
public enum Transformer {}

// MARK: - Module Protocol

extension Transformer {
    /// A transformer module that converts input to output.
    ///
    /// Each module defines:
    /// - `Parameter`: Predefined parameters displayed in a settings UI for user configuration.
    /// - `Input`: Input passed by the caller at runtime.
    /// - `Output`: Output returned to the caller.
    public protocol Module: Codable, Sendable, Hashable {
        /// Predefined parameters, displayed in a settings UI for user configuration.
        associatedtype Parameter: CaseIterable & Hashable & Sendable

        /// Input passed by the caller at runtime.
        associatedtype Input

        /// Output returned to the caller.
        associatedtype Output

        /// Display name for a settings UI.
        static var displayName: String { get }

        /// Whether this module is enabled.
        var isEnabled: Bool { get set }

        /// Applies this module's transformation.
        func transform(_ input: Input) -> Output
    }
}

// MARK: - Swift Configuration

extension Transformer {
    /// Configuration for Swift-specific transformer modules.
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
