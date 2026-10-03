import ArgumentParser
import Foundation
import SwiftSectionKit

struct ObjCDumpCommand: AsyncParsableCommand, Sendable {
    static let configuration: CommandConfiguration = .init(
        commandName: "dump",
        abstract: "Dump every Objective-C declaration in a Mach-O file or dyld shared cache image."
    )

    @OptionGroup
    var machOOptions: ObjCMachOOptionGroup

    @OptionGroup(title: "Generation")
    var generationOptions: ObjCGenerationOptionGroup

    @OptionGroup(title: "Comment Templates")
    var transformerOptions: ObjCTransformerOptionGroup

    @Option(
        name: .shortAndLong,
        help: ArgumentHelp(
            "The kinds of declaration to dump, comma-separated (e.g. classes,protocols). If not specified, all of them are dumped.",
            valueName: "kinds"
        )
    )
    var sections: ObjCSectionKindList?

    @Option(name: .shortAndLong, help: "Only dump declarations whose name contains this text, case-insensitively.")
    var filter: String?

    @Option(name: .shortAndLong, help: "The output path for the dump. If not specified, the output is printed to stdout.", completion: .file())
    var outputPath: String?

    @Option(name: .shortAndLong, help: "The color scheme for the output.")
    var colorScheme: SemanticColorScheme = .none

    @Flag(name: .shortAndLong, help: "Report indexing progress on stderr.")
    var verbose: Bool = false

    /// The library request these flags describe.
    func makeRequest() throws -> ObjCDumpRequest {
        ObjCDumpRequest(
            source: try machOOptions.machOSource(),
            kinds: sections?.kinds,
            nameFilter: filter,
            generation: generationOptions.build(),
            cTypeReplacements: try transformerOptions.buildCTypeReplacements(),
            ivarOffsetComment: transformerOptions.buildIvarOffsetComment(),
            reportsIndexingProgress: verbose,
            imageDescription: machOOptions.imageDescription,
            destination: outputPath.map { .file(path: $0) } ?? .output
        )
    }

    func run() async throws {
        let request = try makeRequest()
        do {
            try await request.run(output: StandardStreamOutput(colorScheme: colorScheme))
        } catch {
            throw CommandLineErrorTranslation.translated(error)
        }
    }

    /// Catches the spelling this option used to accept. `--sections classes protocols`
    /// leaves `protocols` sitting in the positional slot, so the binary would be
    /// looked for under a declaration kind's name — a confusing "no such file"
    /// far from the real mistake.
    ///
    /// Only the two-token shape is recoverable here: with a path as well
    /// (`--sections classes protocols /bin/ls`) the parser rejects the extra
    /// positional argument before `validate()` ever runs.
    func validate() throws {
        guard let sections,
              let filePath = machOOptions.filePath,
              ObjCDeclarationKind(rawValue: filePath) != nil
        else { return }

        let combinedKinds = (sections.kinds.map(\.rawValue) + [filePath]).joined(separator: ",")
        throw ValidationError(
            """
            '\(filePath)' was read as the input path, but it is also a declaration kind. \
            --sections takes one comma-separated value: write '--sections \(combinedKinds)' \
            and put the input path after it.
            """
        )
    }
}
