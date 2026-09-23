import Foundation
import MachOKit
import MachOKitExtensions
import ObjCDeclarationRendering
import ObjCIndexing
import ObjCInterface
import Semantic

/// Everything a command needs after option parsing: the loaded binary, a
/// prepared index over it, and the builder plus the per-request rendering
/// arguments that every `*Interface` call takes.
///
/// Both subcommands do exactly the same setup, and getting it wrong in one of
/// them would show up as a silent difference in output rather than as an
/// error — so it lives in one place.
struct ObjCInterfaceSession {
    let machOFile: MachOFile
    let indexer: ObjCInterfaceIndexer<MachOFile>
    let builder: ObjCInterfaceBuilder<MachOFile>

    private let options: ObjCGenerationOptions
    private let cTypeReplacements: [ObjCPrimitiveTypePattern: String]
    private let ivarOffsetCommentBuilder: (@Sendable (Int) -> String)?

    static func make(
        machOOptions: ObjCMachOOptionGroup,
        generationOptions: ObjCGenerationOptionGroup,
        transformerOptions: ObjCTransformerOptionGroup,
        isVerbose: Bool
    ) async throws -> ObjCInterfaceSession {
        let machOFile = try MachOFile.load(options: machOOptions)

        // The handler is bound at `init`, not at `prepare()`: events are
        // delivered during the walk and nothing is retained afterwards, so
        // there is no way to attach one later and recover them.
        // Progress goes to stderr so that a redirected dump stays a dump.
        let eventHandler: (@Sendable (ObjCIndexingEvent) -> Void)? = isVerbose
            ? { @Sendable event in reportProgress(event) }
            : nil
        let indexer = ObjCInterfaceIndexer(
            machO: machOFile,
            imagePath: machOFile.imagePath,
            eventHandler: eventHandler
        )
        try await indexer.prepare()

        var options = generationOptions.build()
        // A template option on its own would otherwise be silently inert.
        if transformerOptions.impliesIvarOffsetComments {
            options.addIvarOffsetComments = true
        }

        return ObjCInterfaceSession(
            machOFile: machOFile,
            indexer: indexer,
            builder: ObjCInterfaceBuilder(indexer: indexer, machO: machOFile),
            options: options,
            cTypeReplacements: try transformerOptions.buildCTypeReplacements(),
            ivarOffsetCommentBuilder: transformerOptions.buildIvarOffsetCommentBuilder()
        )
    }

    // MARK: - Rendering

    func classInterface(named name: String) -> SemanticString? {
        builder.classInterface(
            named: name,
            options: options,
            cTypeReplacements: cTypeReplacements,
            ivarOffsetCommentBuilder: ivarOffsetCommentBuilder
        )
    }

    func protocolInterface(named name: String) -> SemanticString? {
        builder.protocolInterface(
            named: name,
            options: options,
            cTypeReplacements: cTypeReplacements,
            ivarOffsetCommentBuilder: ivarOffsetCommentBuilder
        )
    }

    func categoryInterface(uniqueName: String) -> SemanticString? {
        builder.categoryInterface(
            uniqueName: uniqueName,
            options: options,
            cTypeReplacements: cTypeReplacements,
            ivarOffsetCommentBuilder: ivarOffsetCommentBuilder
        )
    }

    func structInterface(named name: String) -> SemanticString? {
        builder.structInterface(
            named: name,
            options: options,
            cTypeReplacements: cTypeReplacements,
            ivarOffsetCommentBuilder: ivarOffsetCommentBuilder
        )
    }

    func unionInterface(named name: String) -> SemanticString? {
        builder.unionInterface(
            named: name,
            options: options,
            cTypeReplacements: cTypeReplacements,
            ivarOffsetCommentBuilder: ivarOffsetCommentBuilder
        )
    }

    /// The declaration names of `kind`, sorted, so that two runs over the same
    /// binary print the same thing. The index stores them in dictionaries,
    /// whose iteration order is not stable across runs.
    func names(of kind: ObjCSectionKind) -> [String] {
        switch kind {
        case .classes: indexer.classNames.sorted()
        case .protocols: indexer.protocolNames.sorted()
        case .categories: indexer.categoryNames.sorted()
        case .structs: indexer.structNames.sorted()
        case .unions: indexer.unionNames.sorted()
        }
    }

    /// Whether the index holds no declaration at all, of any kind. This is what
    /// separates "this binary carries no Objective-C metadata" from "the kinds
    /// you asked for happen to be empty in it" — the two are otherwise
    /// indistinguishable from an empty dump.
    var isEmpty: Bool {
        ObjCSectionKind.allCases.allSatisfy { names(of: $0).isEmpty }
    }

    func interface(of kind: ObjCSectionKind, named name: String) -> SemanticString? {
        switch kind {
        case .classes: classInterface(named: name)
        case .protocols: protocolInterface(named: name)
        case .categories: categoryInterface(uniqueName: name)
        case .structs: structInterface(named: name)
        case .unions: unionInterface(named: name)
        }
    }

    // MARK: - Progress

    private static func reportProgress(_ event: ObjCIndexingEvent) {
        guard case .progress(let phase, let itemDescription, let currentCount, let totalCount) = event else {
            return
        }
        let phaseDescription =
            switch phase {
            case .indexingSubclasses: "Indexing subclasses"
            case .indexingConformances: "Indexing conformances"
            case .loadingClasses: "Loading classes"
            case .loadingProtocols: "Loading protocols"
            case .loadingCategories: "Loading categories"
            }
        var line = "\(phaseDescription) \(currentCount)/\(totalCount)"
        if !itemDescription.isEmpty {
            line += " \(itemDescription)"
        }
        writeStandardErrorLine(line)
    }
}
