import ArgumentParser

private let version = "0.8.0-beta.2"

@main
struct SwiftSectionCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "swift-section",
        version: version,
        subcommands: [
            DumpCommand.self,
            InterfaceCommand.self,
        ],
        defaultSubcommand: DumpCommand.self
    )
}
