import Foundation
import OutputTransformer
import SwiftOutputTransformer

/// The comment transformer modules whose tokens and templates can be listed.
///
/// The raw values are the names the command line spells them by.
public enum TransformerModule: String, CaseIterable, Sendable, Hashable {
    case fieldOffset = "field-offset"
    case vtableOffset = "vtable-offset"
    case memberAddress = "member-address"
    case typeLayout = "type-layout"
    case enumLayout = "enum-layout"
}

/// `swift-section transformer tokens`: list the `${token}` placeholders each
/// comment template accepts.
public struct TransformerTokensRequest: Sendable, Equatable {
    /// One module, or `nil` for all of them.
    public var module: TransformerModule?

    public init(module: TransformerModule? = nil) {
        self.module = module
    }

    public func run(output: some SwiftSectionOutput) {
        for (moduleIndex, module) in (module.map { [$0] } ?? TransformerModule.allCases).enumerated() {
            if moduleIndex > 0 {
                output.write(.text(""))
            }
            let description = module.listingDescription
            output.write(.text("\(description.displayName) (\(module.rawValue))"))
            for section in description.tokenSections {
                output.write(.text("  \(section.title) — \(section.optionName)"))
                let widestPlaceholder = section.tokens.map(\.placeholder.count).max() ?? 0
                for token in section.tokens {
                    let padding = String(repeating: " ", count: widestPlaceholder - token.placeholder.count)
                    output.write(.text("    \(token.placeholder)\(padding)  \(token.displayName)"))
                }
            }
        }
    }
}

/// `swift-section transformer templates`: list the built-in comment templates,
/// whose names the template options accept.
public struct TransformerTemplatesRequest: Sendable, Equatable {
    /// One module, or `nil` for all of them.
    public var module: TransformerModule?

    public init(module: TransformerModule? = nil) {
        self.module = module
    }

    public func run(output: some SwiftSectionOutput) {
        for (moduleIndex, module) in (module.map { [$0] } ?? TransformerModule.allCases).enumerated() {
            if moduleIndex > 0 {
                output.write(.text(""))
            }
            let description = module.listingDescription
            output.write(.text("\(description.displayName) (\(module.rawValue))"))
            for section in description.templateSections {
                output.write(.text("  \(section.title) — \(section.optionName)"))
                for template in section.templates {
                    output.write(.text("    \(template.name)"))
                    for line in template.template.components(separatedBy: "\n") {
                        output.write(.text("      \(line)"))
                    }
                }
            }
        }
    }
}

/// `swift-section transformer config`: a comment transformer configuration as
/// pretty-printed JSON, the shape `--transformer-config` reads back.
public struct TransformerConfigurationRequest: Sendable, Equatable {
    public var configuration: Transformer.SwiftConfiguration
    public var destination: ProductDestination

    public init(configuration: Transformer.SwiftConfiguration = .init(), destination: ProductDestination = .output) {
        self.configuration = configuration
        self.destination = destination
    }

    public func run(output: some SwiftSectionOutput) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // JSONEncoder only ever produces UTF-8.
        let encodedString = String(decoding: try encoder.encode(configuration), as: UTF8.self)
        try destination.deliver(encodedString, to: output)
    }
}

// MARK: - Listing

/// One module's listing: which tokens its templates accept, and which built-in
/// templates can be named. The option names are the command line's, since the
/// listing exists to say what to pass to them.
struct TransformerModuleListing {
    struct TokenSection {
        let title: String
        let optionName: String
        let tokens: [(placeholder: String, displayName: String)]
    }

    struct TemplateSection {
        let title: String
        let optionName: String
        let templates: [(name: String, template: String)]
    }

    let displayName: String
    let tokenSections: [TokenSection]
    let templateSections: [TemplateSection]
}

extension TransformerModule {
    var listingDescription: TransformerModuleListing {
        switch self {
        case .fieldOffset:
            .init(
                displayName: Transformer.SwiftFieldOffset.displayName,
                tokenSections: [
                    .init(
                        title: "Tokens",
                        optionName: "--field-offset-template",
                        tokens: Transformer.SwiftFieldOffset.Token.allCases.map { ($0.placeholder, $0.displayName) }
                    ),
                ],
                templateSections: [
                    .init(
                        title: "Templates",
                        optionName: "--field-offset-template",
                        templates: Transformer.SwiftFieldOffset.Templates.all
                    ),
                ]
            )
        case .vtableOffset:
            .init(
                displayName: Transformer.SwiftVTableOffset.displayName,
                tokenSections: [
                    .init(
                        title: "Tokens",
                        optionName: "--vtable-offset-template / --vtable-offset-labeled-template",
                        tokens: Transformer.SwiftVTableOffset.Token.allCases.map { ($0.placeholder, $0.displayName) }
                    ),
                ],
                templateSections: [
                    .init(
                        title: "Templates",
                        optionName: "--vtable-offset-template",
                        templates: Transformer.SwiftVTableOffset.Templates.all
                    ),
                    .init(
                        title: "Labeled Templates",
                        optionName: "--vtable-offset-labeled-template",
                        templates: Transformer.SwiftVTableOffset.Templates.allLabeled
                    ),
                ]
            )
        case .memberAddress:
            .init(
                displayName: Transformer.SwiftMemberAddress.displayName,
                tokenSections: [
                    .init(
                        title: "Tokens",
                        optionName: "--member-address-template",
                        tokens: Transformer.SwiftMemberAddress.Token.allCases.map { ($0.placeholder, $0.displayName) }
                    ),
                ],
                templateSections: [
                    .init(
                        title: "Templates",
                        optionName: "--member-address-template",
                        templates: Transformer.SwiftMemberAddress.Templates.all
                    ),
                ]
            )
        case .typeLayout:
            .init(
                displayName: Transformer.SwiftTypeLayout.displayName,
                tokenSections: [
                    .init(
                        title: "Tokens",
                        optionName: "--type-layout-template",
                        tokens: Transformer.SwiftTypeLayout.Token.allCases.map { ($0.placeholder, $0.displayName) }
                    ),
                ],
                templateSections: [
                    .init(
                        title: "Templates",
                        optionName: "--type-layout-template",
                        templates: Transformer.SwiftTypeLayout.Templates.all
                    ),
                ]
            )
        case .enumLayout:
            .init(
                displayName: Transformer.SwiftEnumLayout.displayName,
                tokenSections: [
                    .init(
                        title: "Strategy Line Tokens",
                        optionName: "--enum-layout-template",
                        tokens: Transformer.SwiftEnumLayout.Token.allCases.map { ($0.placeholder, $0.displayName) }
                    ),
                    .init(
                        title: "Case Tokens",
                        optionName: "--enum-layout-case-template",
                        tokens: Transformer.SwiftEnumLayout.CaseToken.allCases.map { ($0.placeholder, $0.displayName) }
                    ),
                    .init(
                        title: "Fixed-Byte Tokens",
                        optionName: "--enum-layout-byte-template",
                        tokens: Transformer.SwiftEnumLayout.MemoryOffsetToken.allCases.map { ($0.placeholder, $0.displayName) }
                    ),
                ],
                templateSections: [
                    .init(
                        title: "Strategy Line Templates",
                        optionName: "--enum-layout-template",
                        templates: Transformer.SwiftEnumLayout.Templates.all
                    ),
                    .init(
                        title: "Case Templates",
                        optionName: "--enum-layout-case-template",
                        templates: Transformer.SwiftEnumLayout.CaseTemplates.all
                    ),
                    .init(
                        title: "Fixed-Byte Templates",
                        optionName: "--enum-layout-byte-template",
                        templates: Transformer.SwiftEnumLayout.MemoryOffsetTemplates.all
                    ),
                ]
            )
        }
    }
}
