import ArgumentParser
import Foundation
import SwiftSectionKit

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
    // bare spelling is ambiguous wherever both are imported.
    @ArgumentParser.Argument(help: "The name of the declaration to print.")
    var declarationName: String

    @OptionGroup
    var machOOptions: ObjCMachOOptionGroup

    @OptionGroup(title: "Generation")
    var generationOptions: ObjCGenerationOptionGroup

    @OptionGroup(title: "Comment Templates")
    var transformerOptions: ObjCTransformerOptionGroup

    @Option(help: "Only look for the name among declarations of this kind. If not specified, every kind is searched.")
    var kind: ObjCDeclarationKind?

    @Option(name: .shortAndLong, help: "The output path. If not specified, the output is printed to stdout.", completion: .file())
    var outputPath: String?

    @Option(name: .shortAndLong, help: "The color scheme for the output.")
    var colorScheme: SemanticColorScheme = .none

    @Flag(name: .shortAndLong, help: "Report indexing progress on stderr.")
    var verbose: Bool = false

    @Flag(name: .customLong("swift"), help: "Print the declaration as Swift imports it — names by the ClangImporter's rules, members Swift implements as their Swift declarations — instead of as an Objective-C header. Classes, categories and protocols only.")
    var printsSwiftImport: Bool = false

    /// The library request these flags describe.
    func makeRequest() throws -> ObjCInterfaceRequest {
        ObjCInterfaceRequest(
            declarationName: declarationName,
            kind: kind,
            source: try machOOptions.machOSource(),
            generation: generationOptions.build(),
            cTypeReplacements: try transformerOptions.buildCTypeReplacements(),
            ivarOffsetComment: transformerOptions.buildIvarOffsetComment(),
            reportsIndexingProgress: verbose,
            destination: outputPath.map { .file(path: $0) } ?? .output,
            printsSwiftImport: printsSwiftImport
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
}
