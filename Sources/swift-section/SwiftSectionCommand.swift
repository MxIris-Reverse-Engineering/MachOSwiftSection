import ArgumentParser

@main
struct SwiftSectionCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "swift-section",
        subcommands: [
            DumpCommand.self,
            DemangleCommand.self,
        ],
        defaultSubcommand: DumpCommand.self
    )
}
