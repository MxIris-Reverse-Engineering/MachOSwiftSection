import Foundation
import MachOKit
import MachOFoundation
import MachOSwiftSection
import SwiftDeclaration
import SwiftIndexing
import SwiftPrinting
import SwiftInterface
import SwiftDeclarationRendering
import OutputTransformer
import SwiftOutputTransformer
#if os(macOS)
import TypeIndexing
#endif

/// `swift-section interface`: generate a `.swiftinterface` from a binary.
public struct InterfaceRequest: Sendable, Equatable {
    /// Whether `__C` / `__ObjC` type module names are resolved to their real
    /// modules (`__C.NSString` → `Foundation.NSString`).
    public enum CModuleNameResolution: Sendable, Hashable {
        case disabled
        /// Index the SDK modules the binary links, their APINotes and the
        /// dependencies' ObjC metadata. Needs Xcode; the first run per SDK
        /// generates module interfaces through sourcekitd and caches the
        /// extraction. `supplementaryAPINotesPaths` adds `.apinotes` files (or
        /// directories of them) for frameworks with no SDK module, loaded on
        /// top of the SDK's own; later paths override earlier ones.
        case enabled(supplementaryAPINotesPaths: [String])
    }

    public var source: MachOSource
    /// Where the images a standalone binary links are looked for: by the
    /// accessor-thunk reader, the static layout engine and the indexer's
    /// cross-image facts. Named paths are consulted first.
    public var dependencySearchPaths: [DependencySearchPath]
    public var showsCImportedTypes: Bool
    /// Experimental: may fail to parse complex return types.
    public var parsesOpaqueReturnTypes: Bool
    public var cModuleNameResolution: CModuleNameResolution
    public var fieldOffsetComments: FieldOffsetComments
    public var emitsMemberAddresses: Bool
    /// For class methods, computed properties and non-final stored
    /// properties' accessors.
    public var emitsVTableOffsets: Bool
    public var emitsTypeLayout: Bool
    public var emitsEnumLayout: Bool
    /// A `not exported` comment on members none of whose symbols has an
    /// export-trie entry.
    public var emitsExportStatus: Bool
    /// Only the declarations the image exports: types and protocols whose
    /// descriptor symbol has an export-trie entry, extensions targeting them,
    /// and members with at least one exported symbol. `override` / `@objc`
    /// members and anything without export evidence are kept.
    public var printsExportedDeclarationsOnly: Bool
    public var memberSortOrder: SwiftDeclarationMemberSortOrder
    /// Whether an ObjC method tied to its Swift member by the member's name
    /// alone (no symbol behind it) prints as `override`. The tie is recorded
    /// either way.
    public var infersObjCOverridesFromSelectorNames: Bool
    /// A leading header comment: generator, image path, UUID, architecture,
    /// library-evolution detection, unrecoverable-facts notes.
    public var emitsHeader: Bool
    public var commentTransformers: Transformer.SwiftConfiguration?
    public var destination: ProductDestination

    public init(
        source: MachOSource,
        dependencySearchPaths: [DependencySearchPath] = [],
        showsCImportedTypes: Bool = false,
        parsesOpaqueReturnTypes: Bool = false,
        cModuleNameResolution: CModuleNameResolution = .disabled,
        fieldOffsetComments: FieldOffsetComments = .none,
        emitsMemberAddresses: Bool = false,
        emitsVTableOffsets: Bool = false,
        emitsTypeLayout: Bool = false,
        emitsEnumLayout: Bool = false,
        emitsExportStatus: Bool = false,
        printsExportedDeclarationsOnly: Bool = false,
        memberSortOrder: SwiftDeclarationMemberSortOrder = .byCategory,
        infersObjCOverridesFromSelectorNames: Bool = false,
        emitsHeader: Bool = false,
        commentTransformers: Transformer.SwiftConfiguration? = nil,
        destination: ProductDestination = .output
    ) {
        self.source = source
        self.dependencySearchPaths = dependencySearchPaths
        self.showsCImportedTypes = showsCImportedTypes
        self.parsesOpaqueReturnTypes = parsesOpaqueReturnTypes
        self.cModuleNameResolution = cModuleNameResolution
        self.fieldOffsetComments = fieldOffsetComments
        self.emitsMemberAddresses = emitsMemberAddresses
        self.emitsVTableOffsets = emitsVTableOffsets
        self.emitsTypeLayout = emitsTypeLayout
        self.emitsEnumLayout = emitsEnumLayout
        self.emitsExportStatus = emitsExportStatus
        self.printsExportedDeclarationsOnly = printsExportedDeclarationsOnly
        self.memberSortOrder = memberSortOrder
        self.infersObjCOverridesFromSelectorNames = infersObjCOverridesFromSelectorNames
        self.emitsHeader = emitsHeader
        self.commentTransformers = commentTransformers
        self.destination = destination
    }

    public func run(output: some SwiftSectionOutput, environment: SwiftSectionEnvironment) async throws {
        try await withAccessorThunkResolver(searchPaths: dependencySearchPaths) {
            try await buildInterface(output: output, environment: environment)
        }
    }

    private func buildInterface(output: some SwiftSectionOutput, environment: SwiftSectionEnvironment) async throws {
        let machOFile = try source.load()

        var printConfiguration = SwiftDeclarationPrintConfiguration(
            printStrippedSymbolicItem: true,
            printFieldOffset: fieldOffsetComments != .none,
            printExpandedFieldOffsets: fieldOffsetComments == .expanded,
            printMemberAddress: emitsMemberAddresses,
            printVTableOffset: emitsVTableOffsets,
            printExportStatus: emitsExportStatus,
            printExportedDeclarationsOnly: printsExportedDeclarationsOnly,
            memberSortOrder: memberSortOrder,
            printTypeLayout: emitsTypeLayout,
            printEnumLayout: emitsEnumLayout
        )
        // Without a configuration the transformer slots stay empty, keeping
        // the built-in rendering byte-for-byte identical.
        if let commentTransformers {
            printConfiguration.applyTransformersEnablingCommentKinds(commentTransformers)
        }
        printConfiguration.staticLayoutDependencyResolution = dependencySearchPaths.staticLayoutDependencyResolution
        // The index records the name-only ObjC tie either way; this decides
        // whether it prints as `@objc override`.
        printConfiguration.infersObjCOverridesFromSelectorNames = infersObjCOverridesFromSelectorNames

        var configuration = SwiftInterfaceBuilderConfiguration(
            indexConfiguration: .init(
                showCImportedTypes: showsCImportedTypes,
                dependencySearchPaths: dependencySearchPaths.indexingSearchPaths
            ),
            printConfiguration: printConfiguration
        )

        if emitsHeader {
            // The header's dispatch-thunk count triggers the symbol-index
            // build (which `prepare()` below then reuses), so progress is
            // announced BEFORE it — otherwise nothing is heard for the whole
            // index build.
            output.reportProgress("Preparing to build Swift interface...")
            configuration.interfaceHeaderInfo = InterfaceHeaderInfo(
                machO: machOFile,
                generatorName: environment.generator.name,
                generatorVersion: environment.generator.version
            )
        }

        let builder = try SwiftInterfaceBuilder(
            configuration: configuration,
            eventHandlers: output.indexEventHandlers(forInputLabeled: nil),
            in: machOFile
        )

        if parsesOpaqueReturnTypes {
            builder.addExtraDataProvider(SwiftInterfaceBuilderOpaqueTypeProvider(machO: machOFile))
        }

        if case .enabled(let supplementaryAPINotesPaths) = cModuleNameResolution {
            addTypeNameProvider(to: builder, machOFile: machOFile, supplementaryAPINotesPaths: supplementaryAPINotesPaths, output: output)
        }

        if !emitsHeader {
            output.reportProgress("Preparing to build Swift interface...")
        }

        try await builder.prepare()

        output.reportProgress("Building Swift interface...")

        let interfaceString = try await builder.printRoot()

        output.reportProgress("Swift interface built successfully.")

        switch destination {
        case .file(let path):
            output.reportProgress("Writing Swift interface to \(path)...")
            try interfaceString.string.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
        case .output:
            output.write(.declarations(interfaceString))
        }
    }

    private func addTypeNameProvider(
        to builder: SwiftInterfaceBuilder<MachOFile>,
        machOFile: MachOFile,
        supplementaryAPINotesPaths: [String],
        output: some SwiftSectionOutput
    ) {
        #if os(macOS)
        guard #available(macOS 13.0, *) else {
            output.reportWarning("warning: --resolve-c-module-names requires macOS 13 or later")
            return
        }
        let providerDependencies = SwiftInterfaceBuilderDependencies(
            machO: machOFile,
            searchPaths: [.systemDyldSharedCache],
            eventHandlers: output.indexEventHandlers(forInputLabeled: nil)
        )
        // Dependency resolution against the HOST dyld cache matches install
        // names exactly, then bare names; a non-macOS binary's paths mostly
        // miss both, which silently guts the SDK-interface source. Said
        // aloud, misses named, instead of degrading quietly.
        if providerDependencies.dependencies.isEmpty {
            output.reportWarning("warning: --resolve-c-module-names resolved no dependency images against this host (non-macOS binary?); attribution will be limited to SDK APINotes and supplementary files")
        } else if !providerDependencies.unresolvedLoadNames.isEmpty {
            output.reportWarning("warning: --resolve-c-module-names could not resolve \(providerDependencies.unresolvedLoadNames.count) dependency image(s) against this host; their types will not be attributed: \(providerDependencies.unresolvedLoadNames.joined(separator: ", "))")
        }
        // A bad supplementary path is otherwise only os_log'd by the library
        // floor; a mistyped path or a broken YAML deserves the same warning
        // the other degradations get. (Files inside a directory argument stay
        // on the library's skip-and-log contract.)
        for supplementaryAPINotesPath in supplementaryAPINotesPaths {
            var pathIsDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: supplementaryAPINotesPath, isDirectory: &pathIsDirectory) else {
                output.reportWarning("warning: --supplementary-apinotes path does not exist: \(supplementaryAPINotesPath)")
                continue
            }
            if !pathIsDirectory.boolValue {
                do {
                    _ = try APINotesFile(path: supplementaryAPINotesPath)
                } catch {
                    output.reportWarning("warning: --supplementary-apinotes file failed to parse and will be skipped: \(supplementaryAPINotesPath): \(error)")
                }
            }
        }
        let supplementaryAPINotesURLs = supplementaryAPINotesPaths.map { URL(fileURLWithPath: $0) }
        if let typeNameProvider = SwiftInterfaceBuilderTypeNameProvider(machO: machOFile, dependencies: providerDependencies, supplementaryAPINotesURLs: supplementaryAPINotesURLs) {
            builder.addExtraDataProvider(typeNameProvider)
        } else {
            output.reportWarning("warning: --resolve-c-module-names ignored: the binary carries no build-version command mapping to a known SDK platform")
        }
        #else
        output.reportWarning("warning: --resolve-c-module-names is only available on macOS")
        #endif
    }
}
