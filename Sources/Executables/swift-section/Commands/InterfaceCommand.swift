import Foundation
import ArgumentParser
import SwiftSectionKit

struct InterfaceCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "interface",
        abstract: "Generate Swift interface from a Mach-O file."
    )

    @OptionGroup
    var machOOptions: MachOOptionGroup

    @OptionGroup
    var objcMemberOptions: ObjCMemberOptionGroup

    @OptionGroup(title: "Comment Templates")
    var transformerOptions: TransformerOptionGroup

    @Option(name: .shortAndLong, help: "The output path for the dump. If not specified, the output will be printed to the console.", completion: .file())
    var outputPath: String?

    @Flag(help: "Show imported C types in the generated Swift interface.")
    var showCImportedTypes: Bool = false

    @Flag(help: "Parse opaque return value, this option is an experimental feature and may result in parsing errors for complex return types.")
    var parseOpaqueReturnType: Bool = false

    @Flag(help: "Resolve __C/__ObjC type module names to their real modules (__C.NSString -> Foundation.NSString) by indexing the SDK modules the binary links, its APINotes, and its dependencies' ObjC metadata. Requires Xcode; the first run per SDK generates module interfaces through sourcekitd and caches the extraction.")
    var resolveCModuleNames: Bool = false

    @Option(name: .customLong("supplementary-apinotes"), help: "A supplementary .apinotes file (or a directory of them) of user-provided type mappings for frameworks with no SDK module (e.g. AttributeGraph), loaded on top of the SDK's own APINotes. Repeatable; later paths override earlier ones. Only used with --resolve-c-module-names.", completion: .file())
    var supplementaryAPINotesPaths: [String] = []

    @Flag(help: "Generate field offset and PWT offset comments, if possible")
    var emitOffsetComments: Bool = false

    @Flag(help: "Generate member address comments for each member symbol")
    var emitMemberAddresses: Bool = false

    @Flag(help: "Generate vtable offset comments for class methods, computed properties, and non-final stored properties' accessors")
    var emitVtableOffsets: Bool = false

    @Flag(help: "Expand nested struct fields with their absolute offsets (implies --emit-offset-comments)")
    var emitExpandedFieldOffsets: Bool = false

    @Flag(help: "Generate type layout (size/stride/alignment) comments, computed statically via SwiftLayout")
    var emitTypeLayout: Bool = false

    @Flag(help: "Generate enum layout (strategy/per-case/spare-bit) comments, computed statically via SwiftLayout")
    var emitEnumLayout: Bool = false

    @Flag(help: "Sort members by binary layout offset instead of grouping by category")
    var sortMembersByOffset: Bool = false

    @Flag(help: "Emit a leading header comment block (generator, image path, UUID, architecture, library-evolution detection, unrecoverable-facts notes)")
    var emitHeader: Bool = false

    @Flag(help: "Annotate members none of whose symbols have an export-trie entry with a `not exported` comment")
    var emitExportStatus: Bool = false

    @Flag(name: .customLong("exported-only"), help: "Print only the declarations the image exports: types and protocols whose descriptor symbol has an export-trie entry, extensions targeting them, and members with at least one exported symbol (dispatch-thunk and other derived forms included). `override` / `@objc` members and anything without export evidence are kept.")
    var exportedOnly: Bool = false

    @Option(name: .shortAndLong, help: "The color scheme for the output.")
    var colorScheme: SemanticColorScheme = .none

    /// The library request these flags describe.
    func makeRequest() throws -> InterfaceRequest {
        InterfaceRequest(
            source: try machOOptions.machOSource(),
            dependencySearchPaths: machOOptions.dependencySearchPathValues,
            showsCImportedTypes: showCImportedTypes,
            parsesOpaqueReturnTypes: parseOpaqueReturnType,
            cModuleNameResolution: resolveCModuleNames ? .enabled(supplementaryAPINotesPaths: supplementaryAPINotesPaths) : .disabled,
            fieldOffsetComments: emitExpandedFieldOffsets ? .expanded : (emitOffsetComments ? .flat : .none),
            emitsMemberAddresses: emitMemberAddresses,
            emitsVTableOffsets: emitVtableOffsets,
            emitsTypeLayout: emitTypeLayout,
            emitsEnumLayout: emitEnumLayout,
            emitsExportStatus: emitExportStatus,
            printsExportedDeclarationsOnly: exportedOnly,
            memberSortOrder: sortMembersByOffset ? .byOffset : .byCategory,
            infersObjCOverridesFromSelectorNames: objcMemberOptions.infersOverridesFromSelectorNames,
            emitsHeader: emitHeader,
            commentTransformers: try transformerOptions.buildTransformerConfiguration(),
            destination: outputPath.map { .file(path: $0) } ?? .output
        )
    }

    func run() async throws {
        let request = try makeRequest()
        // Progress lines have always gone to stdout here, mixed into the
        // product unless `-o` is given.
        let output = StandardStreamOutput(colorScheme: colorScheme, standardOutputSeverities: [.progress])
        if !resolveCModuleNames, !supplementaryAPINotesPaths.isEmpty {
            output.report(SwiftSectionDiagnostic(severity: .warning, message: "warning: --supplementary-apinotes has no effect without --resolve-c-module-names"))
        }
        do {
            try await request.run(output: output, environment: .commandLine)
        } catch {
            throw CommandLineErrorTranslation.translated(error)
        }
    }
}
