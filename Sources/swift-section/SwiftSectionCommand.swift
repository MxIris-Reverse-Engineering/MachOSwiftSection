import ArgumentParser

@main
struct SwiftSectionCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "swift-section",
        version: BundledVersion.value,
        subcommands: [
            DumpCommand.self,
            InterfaceCommand.self,
        ],
        defaultSubcommand: DumpCommand.self
    )
}
