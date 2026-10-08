import Foundation
import ArgumentParser
import SwiftSectionKit

struct DumpCommand: AsyncParsableCommand, Sendable {
    static let configuration: CommandConfiguration = .init(
        commandName: "dump",
        abstract: "Dump Swift information from a Mach-O file or dyld shared cache."
    )

    @OptionGroup
    var machOOptions: MachOOptionGroup

    @OptionGroup
    var demangleOptions: DemangleOptionGroup

    @OptionGroup(title: "Comment Templates")
    var transformerOptions: TransformerOptionGroup

    @Option(name: .shortAndLong, help: "The output path for the dump. If not specified, the output will be printed to the console.", completion: .file())
    var outputPath: String?

    @Option(name: .shortAndLong, parsing: .upToNextOption, help: "The sections to dump. If not specified, all sections will be dumped.")
    var sections: [DumpSection] = []

    @Option(name: .shortAndLong, help: "The color scheme for the output.")
    var colorScheme: SemanticColorScheme = .none

    @Flag(help: "Generate member address comments for each member symbol")
    var emitMemberAddresses: Bool = false

    @Flag(help: "Generate vtable offset comments for class methods")
    var emitVtableOffsets: Bool = false

    @Flag(help: "Generate PWT (Protocol Witness Table) address comments for protocol conformances")
    var emitPWTAddresses: Bool = false

    @Flag(help: "Generate field offset comments for struct/class stored properties, computed statically via SwiftLayout")
    var emitFieldOffsets: Bool = false

    @Flag(help: "Generate type layout (size/stride/alignment) comments, computed statically via SwiftLayout")
    var emitTypeLayout: Bool = false

    @Flag(help: "Generate enum layout (strategy/per-case/spare-bit) comments, computed statically via SwiftLayout")
    var emitEnumLayout: Bool = false

    @Flag(help: "Expand nested struct fields with their absolute offsets (implies --emit-field-offsets)")
    var emitExpandedFieldOffsets: Bool = false

    @Flag(help: "The definitions of types and protocols will be output in the order they are stored in the binary.")
    var preferredBinaryOrder: Bool = false

    @Flag(help: "Emit a leading header comment block (generator, image path, UUID, architecture, library-evolution detection, unrecoverable-facts notes)")
    var emitHeader: Bool = false

    @Flag(help: "Annotate member-symbol lines whose symbol has no export-trie entry with a `not exported` comment")
    var emitExportStatus: Bool = false

    /// The library request these flags describe.
    func makeRequest() throws -> DumpRequest {
        DumpRequest(
            source: try machOOptions.machOSource(),
            dependencySearchPaths: machOOptions.dependencySearchPathValues,
            sections: sections.isEmpty ? .all : .only(sections),
            ordering: preferredBinaryOrder ? .binaryOrder : .bySection,
            demangleOptions: demangleOptions.buildSwiftDumpDemangleOptions(),
            fieldOffsetComments: emitExpandedFieldOffsets ? .expanded : (emitFieldOffsets ? .flat : .none),
            emitsMemberAddresses: emitMemberAddresses,
            emitsVTableOffsets: emitVtableOffsets,
            emitsProtocolWitnessTableAddresses: emitPWTAddresses,
            emitsTypeLayout: emitTypeLayout,
            emitsEnumLayout: emitEnumLayout,
            emitsExportStatus: emitExportStatus,
            emitsHeader: emitHeader,
            commentTransformers: try transformerOptions.buildTransformerConfiguration(),
            destination: outputPath.map { .file(path: $0) } ?? .output
        )
    }

    func run() async throws {
        let request = try makeRequest()
        do {
            try await request.run(
                output: StandardStreamOutput(colorScheme: colorScheme, standardOutputSeverities: [.error]),
                environment: .commandLine
            )
        } catch {
            throw CommandLineErrorTranslation.translated(error)
        }
    }
}
