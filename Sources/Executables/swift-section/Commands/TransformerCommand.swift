import ArgumentParser
import Foundation
import SwiftSectionKit

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
        var module: TransformerModule?

        func run() throws {
            TransformerTokensRequest(module: module).run(output: StandardStreamOutput())
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
        var module: TransformerModule?

        func run() throws {
            TransformerTemplatesRequest(module: module).run(output: StandardStreamOutput())
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
            try TransformerConfigurationRequest(
                configuration: transformerOptions.buildTransformerConfiguration() ?? .init(),
                destination: outputPath.map { .file(path: $0) } ?? .output
            ).run(output: StandardStreamOutput())
        }
    }
}
