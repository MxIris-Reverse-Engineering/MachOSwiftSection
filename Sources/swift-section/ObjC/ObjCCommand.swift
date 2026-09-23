import ArgumentParser

/// `swift-section objc …`: the Objective-C side of a binary — its declarations
/// as headers, and its API diffed across versions.
///
/// These five subcommands used to ship as a separate `objc-section` executable
/// from the MachOObjCSection repository. They moved here unchanged — the same
/// options, output and exit codes — so that one tool, one version and one
/// release cover both languages. The ObjC libraries they are built on still
/// live in MachOObjCSection.
struct ObjCCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "objc",
        abstract: "Dump Objective-C declarations out of a Mach-O file or dyld shared cache, and diff their API.",
        subcommands: [
            ObjCDumpCommand.self,
            ObjCInterfaceCommand.self,
            ObjCSnapshotCommand.self,
            ObjCDiffCommand.self,
            ObjCEvolutionCommand.self,
        ],
        defaultSubcommand: ObjCDumpCommand.self
    )
}
