import ArgumentParser
import Foundation
import MachOKit
import Semantic

struct ObjCInterfaceCommand: AsyncParsableCommand, Sendable {
    static let configuration: CommandConfiguration = .init(
        commandName: "interface",
        abstract: "Print the interface of one Objective-C declaration.",
        discussion: """
        The name is a class name (NSString), a protocol name (NSCopying), or a \
        category's unique name in ClassName(CategoryName) form. Struct and \
        union names are accepted too.
        """
    )

    // Fully qualified: `Semantic` exports an `Argument` of its own, so the
    // bare spelling is ambiguous here.
    @ArgumentParser.Argument(help: "The name of the declaration to print.")
    var declarationName: String

    @OptionGroup
    var machOOptions: ObjCMachOOptionGroup

    @OptionGroup(title: "Generation")
    var generationOptions: ObjCGenerationOptionGroup

    @OptionGroup(title: "Comment Templates")
    var transformerOptions: ObjCTransformerOptionGroup

    @Option(help: "Only look for the name among declarations of this kind. If not specified, every kind is searched.")
    var kind: ObjCSectionKind?

    @Option(name: .shortAndLong, help: "The output path. If not specified, the output is printed to stdout.", completion: .file())
    var outputPath: String?

    @Option(name: .shortAndLong, help: "The color scheme for the output.")
    var colorScheme: SemanticColorScheme = .none

    @Flag(name: .shortAndLong, help: "Report indexing progress on stderr.")
    var verbose: Bool = false

    func run() async throws {
        let session = try await ObjCInterfaceSession.make(
            machOOptions: machOOptions,
            generationOptions: generationOptions,
            transformerOptions: transformerOptions,
            isVerbose: verbose
        )

        // Searched in declaration-kind order rather than by guessing from the
        // spelling: `Foo(Bar)` is unambiguous, but a bare name could be a
        // class, a protocol or a struct, and binaries do reuse a name across
        // those. `--kind` is how a caller settles it.
        let kinds = kind.map { [$0] } ?? ObjCSectionKind.allCases

        for candidateKind in kinds {
            guard let interface = session.interface(of: candidateKind, named: declarationName) else { continue }
            if let outputPath {
                try interface.string.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
            } else {
                interface.printColorfully(using: colorScheme)
            }
            return
        }

        throw ObjCSectionCommandError.declarationNotFound(declarationName)
    }
}
