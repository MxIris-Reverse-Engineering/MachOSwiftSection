import ArgumentParser
#if THUNK_ANALYSIS
import SwiftDeclarationRendering
import SwiftThunkAnalysis
#endif

@main
struct SwiftSectionCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "swift-section",
        version: BundledVersion.value,
        subcommands: [
            DumpCommand.self,
            InterfaceCommand.self,
            DiffCommand.self,
            SnapshotCommand.self,
            EvolutionCommand.self,
            TransformerCommand.self,
        ],
        defaultSubcommand: DumpCommand.self
    )

    /// Overridden so registration happens for **every** invocation.
    ///
    /// A root command's `init()` runs only when the root command itself runs;
    /// `swift-section dump …` instantiates `DumpCommand` and never touches
    /// this type's initializer, so registering there would silently do nothing
    /// for every subcommand — which is all of them.
    static func main() async {
        #if THUNK_ANALYSIS
        // Built with the `ThunkAnalysis` trait, so a kind-9 accessor-function
        // symbolic reference renders as the type it stands for instead of a
        // bare address. Registered unconditionally because for a CLI the trait
        // *is* the opt-in — there is no separate user setting to consult, as
        // there would be in a GUI host.
        AccessorThunkResolution.installDisassemblingResolver()
        #endif
        await main(nil)
    }
}
