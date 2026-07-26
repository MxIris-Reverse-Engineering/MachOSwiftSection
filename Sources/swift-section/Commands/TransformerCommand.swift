import ArgumentParser
import Foundation
import OutputTransformer

// MARK: - Module Selector

/// The comment transformer modules addressable from the command line.
enum TransformerModuleSelector: String, ExpressibleByArgument, CaseIterable {
    case fieldOffset = "field-offset"
    case vtableOffset = "vtable-offset"
    case memberAddress = "member-address"
    case typeLayout = "type-layout"
    case enumLayout = "enum-layout"

    var description: TransformerModuleDescription {
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

/// One module's command-line-facing surface: which tokens its templates accept
/// and which built-in templates can be named.
struct TransformerModuleDescription {
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

// MARK: - Command

struct TransformerCommand: ParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "transformer",
        abstract: "Inspect and build the comment transformer configuration used by `dump` and `interface`.",
        discussion: """
        Comment templates substitute ${token} placeholders. Use `tokens` to see what each \
        module's templates accept, `templates` to see the built-in templates (their names can \
        be passed to the template options directly), and `config` to produce a JSON \
        configuration for --transformer-config.
        """,
        subcommands: [
            TokensCommand.self,
            TemplatesCommand.self,
            ConfigCommand.self,
        ],
        defaultSubcommand: TokensCommand.self
    )
}

// MARK: - Tokens

extension TransformerCommand {
    struct TokensCommand: ParsableCommand {
        static let configuration: CommandConfiguration = .init(
            commandName: "tokens",
            abstract: "List the ${token} placeholders each comment template accepts."
        )

        @Option(name: .shortAndLong, help: "Restrict the listing to one module. If not specified, all modules are listed.")
        var module: TransformerModuleSelector?

        func run() throws {
            let selectors = module.map { [$0] } ?? TransformerModuleSelector.allCases
            for (index, selector) in selectors.enumerated() {
                if index > 0 { print("") }
                let description = selector.description
                print("\(description.displayName) (\(selector.rawValue))")
                for section in description.tokenSections {
                    print("  \(section.title) — \(section.optionName)")
                    let widestPlaceholder = section.tokens.map(\.placeholder.count).max() ?? 0
                    for token in section.tokens {
                        let padding = String(repeating: " ", count: widestPlaceholder - token.placeholder.count)
                        print("    \(token.placeholder)\(padding)  \(token.displayName)")
                    }
                }
            }
        }
    }
}

// MARK: - Templates

extension TransformerCommand {
    struct TemplatesCommand: ParsableCommand {
        static let configuration: CommandConfiguration = .init(
            commandName: "templates",
            abstract: "List the built-in comment templates. Their names are accepted by the template options."
        )

        @Option(name: .shortAndLong, help: "Restrict the listing to one module. If not specified, all modules are listed.")
        var module: TransformerModuleSelector?

        func run() throws {
            let selectors = module.map { [$0] } ?? TransformerModuleSelector.allCases
            for (index, selector) in selectors.enumerated() {
                if index > 0 { print("") }
                let description = selector.description
                print("\(description.displayName) (\(selector.rawValue))")
                for section in description.templateSections {
                    print("  \(section.title) — \(section.optionName)")
                    for template in section.templates {
                        print("    \(template.name)")
                        for line in template.template.components(separatedBy: "\n") {
                            print("      \(line)")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Config

extension TransformerCommand {
    struct ConfigCommand: ParsableCommand {
        static let configuration: CommandConfiguration = .init(
            commandName: "config",
            abstract: "Print the transformer configuration described by the given options as JSON.",
            discussion: """
            Without any option this prints the all-defaults skeleton, a starting point to edit \
            and feed back through --transformer-config. With options it prints what those \
            options resolve to, so a command line can be frozen into a reusable file.
            """
        )

        @OptionGroup
        var transformerOptions: TransformerOptionGroup

        @Option(name: .shortAndLong, help: "The output path for the configuration. If not specified, it is printed to the console.", completion: .file())
        var outputPath: String?

        func run() throws {
            let configuration = try transformerOptions.buildTransformerConfiguration() ?? .init()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let encodedData = try encoder.encode(configuration)
            guard let encodedString = String(data: encodedData, encoding: .utf8) else {
                throw ValidationError("The transformer configuration could not be encoded as UTF-8 text.")
            }
            if let outputPath {
                try encodedString.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
            } else {
                print(encodedString)
            }
        }
    }
}
