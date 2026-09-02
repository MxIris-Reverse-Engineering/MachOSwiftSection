import SwiftDeclaration
import SwiftIndexing
import SwiftPrinting
import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftInterface
import ArgumentParser
#if os(macOS)
import TypeIndexing
#endif

struct InterfaceCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = .init(
        commandName: "interface",
        abstract: "Generate Swift interface from a Mach-O file."
    )

    @OptionGroup
    var machOOptions: MachOOptionGroup

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

    func run() async throws {
        let machOFile = try MachOFile.load(options: machOOptions)

        let effectiveEmitOffsetComments = emitOffsetComments || emitExpandedFieldOffsets

        var printConfiguration = SwiftDeclarationPrintConfiguration(
            printStrippedSymbolicItem: true,
            printFieldOffset: effectiveEmitOffsetComments,
            printExpandedFieldOffsets: emitExpandedFieldOffsets,
            printMemberAddress: emitMemberAddresses,
            printVTableOffset: emitVtableOffsets,
            printExportStatus: emitExportStatus,
            printExportedDeclarationsOnly: exportedOnly,
            memberSortOrder: sortMembersByOffset ? .byOffset : .byCategory,
            printTypeLayout: emitTypeLayout,
            printEnumLayout: emitEnumLayout
        )

        // Without any template option the slots stay empty, keeping the
        // built-in rendering byte-for-byte identical.
        if let transformers = try transformerOptions.buildTransformerConfiguration() {
            printConfiguration.applyTransformersEnablingCommentKinds(transformers)
        }

        var configuration = SwiftInterfaceBuilderConfiguration(
            indexConfiguration: .init(
                showCImportedTypes: showCImportedTypes
            ),
            printConfiguration: printConfiguration
        )

        if emitHeader {
            // The factory's dispatch-thunk count triggers the symbol-index
            // build (which `prepare()` below then reuses), so announce
            // progress BEFORE it — otherwise the tool sits silent for the
            // whole index build.
            print("Preparing to build Swift interface...")
            configuration.interfaceHeaderInfo = InterfaceHeaderInfo(
                machO: machOFile,
                generatorName: "swift-section",
                generatorVersion: BundledVersion.value
            )
        }

        let builder = try SwiftInterfaceBuilder(configuration: configuration, eventHandlers: [ConsoleEventHandler()], in: machOFile)

        if parseOpaqueReturnType {
            builder.addExtraDataProvider(SwiftInterfaceBuilderOpaqueTypeProvider(machO: machOFile))
        }

        if resolveCModuleNames {
            #if os(macOS)
            if #available(macOS 13.0, *) {
                let providerDependencies = SwiftInterfaceBuilderDependencies(
                    machO: machOFile,
                    paths: [.usesSystemDyldSharedCache],
                    eventHandlers: [ConsoleEventHandler()]
                )
                // Dependency resolution against the HOST dyld cache matches
                // install names exactly; a non-macOS binary's paths mostly
                // miss, which silently guts the SDK-interface source. Say so
                // instead of degrading quietly.
                if providerDependencies.dependencies.isEmpty {
                    fputs("warning: --resolve-c-module-names resolved no dependency images against this host (non-macOS binary?); attribution will be limited to SDK APINotes and supplementary files\n", stderr)
                }
                // Bad supplementary paths are otherwise only os_log'd by the
                // library floor; a CLI user who mistyped a path or handed a
                // broken YAML deserves the same stderr warning the other
                // degradations get. (Files inside a directory argument stay
                // on the library's skip-and-log contract.)
                for supplementaryAPINotesPath in supplementaryAPINotesPaths {
                    var pathIsDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: supplementaryAPINotesPath, isDirectory: &pathIsDirectory) else {
                        fputs("warning: --supplementary-apinotes path does not exist: \(supplementaryAPINotesPath)\n", stderr)
                        continue
                    }
                    if !pathIsDirectory.boolValue {
                        do {
                            _ = try APINotesFile(path: supplementaryAPINotesPath)
                        } catch {
                            fputs("warning: --supplementary-apinotes file failed to parse and will be skipped: \(supplementaryAPINotesPath): \(error)\n", stderr)
                        }
                    }
                }
                let supplementaryAPINotesURLs = supplementaryAPINotesPaths.map { URL(fileURLWithPath: $0) }
                if let typeNameProvider = SwiftInterfaceBuilderTypeNameProvider(machO: machOFile, dependencies: providerDependencies, supplementaryAPINotesURLs: supplementaryAPINotesURLs) {
                    builder.addExtraDataProvider(typeNameProvider)
                } else {
                    fputs("warning: --resolve-c-module-names ignored: the binary carries no build-version command mapping to a known SDK platform\n", stderr)
                }
            } else {
                fputs("warning: --resolve-c-module-names requires macOS 13 or later\n", stderr)
            }
            #else
            fputs("warning: --resolve-c-module-names is only available on macOS\n", stderr)
            #endif
        } else if !supplementaryAPINotesPaths.isEmpty {
            fputs("warning: --supplementary-apinotes has no effect without --resolve-c-module-names\n", stderr)
        }

        if !emitHeader {
            print("Preparing to build Swift interface...")
        }

        try await builder.prepare()

        print("Building Swift interface...")

        let interfaceString = try await builder.printRoot()

        print("Swift interface built successfully.")

        if let outputPath {
            print("Writing Swift interface to \(outputPath)...")
            let outputURL = URL(fileURLWithPath: outputPath)
            try interfaceString.string.write(to: outputURL, atomically: true, encoding: .utf8)
        } else {
            interfaceString.printColorfully(using: colorScheme)
        }
    }
}
