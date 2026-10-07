import Foundation
import MachOKit
import MachOKitExtensions
import ObjCDeclarationRendering
import ObjCIndexing
import ObjCInterface
import ObjCMetadataSource
import ObjCOutputTransformer
import OutputTransformer
import Semantic

/// The kinds of Objective-C declaration `objc dump` and `objc interface` can
/// print. With none given, `objc dump` prints all of them in this order.
///
/// The raw values are the names the command line spells them by.
public enum ObjCDeclarationKind: String, CaseIterable, Sendable, Hashable {
    case classes
    case protocols
    case categories
    case structs
    case unions
}

/// Everything `objc dump` and `objc interface` need once the request is known:
/// the loaded binary, a prepared index over it, and the builder plus the
/// per-request rendering arguments every interface call takes.
///
/// Both requests do exactly the same setup, and getting it wrong in one of
/// them would show up as a silent difference in output rather than as an
/// error, so it lives in one place.
struct ObjCInterfaceSession {
    let machOFile: MachOFile
    let indexer: ObjCInterfaceIndexer<MachOFile>
    let builder: ObjCInterfaceBuilder<MachOFile>

    private let options: ObjCGenerationOptions
    private let cTypeReplacements: [ObjCPrimitiveTypePattern: String]
    private let ivarOffsetCommentBuilder: (@Sendable (Int) -> String)?

    static func make(
        source: MachOSource,
        generation: ObjCGenerationOptions,
        cTypeReplacements: [ObjCPrimitiveTypePattern: String],
        ivarOffsetComment: Transformer.ObjCIvarOffset?,
        reportsIndexingProgress: Bool,
        output: some SwiftSectionOutput
    ) async throws -> ObjCInterfaceSession {
        let machOFile = try source.load()

        // The handler is bound at `init`, not at `prepare()`: events are
        // delivered during the walk and nothing is retained afterwards, so
        // there is no way to attach one later and recover them.
        let eventHandler: (@Sendable (ObjCIndexingEvent) -> Void)? = reportsIndexingProgress
            ? { @Sendable event in reportProgress(event, to: output) }
            : nil
        let indexer = ObjCInterfaceIndexer(
            machO: machOFile,
            imagePath: machOFile.imagePath,
            eventHandler: eventHandler
        )
        try await indexer.prepare()

        var options = generation
        var ivarOffsetCommentBuilder: (@Sendable (Int) -> String)?
        if let ivarOffsetComment {
            ivarOffsetCommentBuilder = { offset in ivarOffsetComment.transform(.init(offset: offset)) }
            // A custom ivar-offset wording on its own would otherwise be
            // silently inert.
            options.addIvarOffsetComments = true
        }

        return ObjCInterfaceSession(
            machOFile: machOFile,
            indexer: indexer,
            builder: ObjCInterfaceBuilder(indexer: indexer, machO: machOFile),
            options: options,
            cTypeReplacements: cTypeReplacements,
            ivarOffsetCommentBuilder: ivarOffsetCommentBuilder
        )
    }

    // MARK: - Rendering

    func interface(of kind: ObjCDeclarationKind, named name: String) -> SemanticString? {
        switch kind {
        case .classes:
            builder.classInterface(
                named: name,
                options: options,
                cTypeReplacements: cTypeReplacements,
                ivarOffsetCommentBuilder: ivarOffsetCommentBuilder
            )
        case .protocols:
            builder.protocolInterface(
                named: name,
                options: options,
                cTypeReplacements: cTypeReplacements,
                ivarOffsetCommentBuilder: ivarOffsetCommentBuilder
            )
        case .categories:
            builder.categoryInterface(
                uniqueName: name,
                options: options,
                cTypeReplacements: cTypeReplacements,
                ivarOffsetCommentBuilder: ivarOffsetCommentBuilder
            )
        case .structs:
            builder.structInterface(
                named: name,
                options: options,
                cTypeReplacements: cTypeReplacements,
                ivarOffsetCommentBuilder: ivarOffsetCommentBuilder
            )
        case .unions:
            builder.unionInterface(
                named: name,
                options: options,
                cTypeReplacements: cTypeReplacements,
                ivarOffsetCommentBuilder: ivarOffsetCommentBuilder
            )
        }
    }

    /// The declaration names of `kind`, sorted, so that two runs over the same
    /// binary print the same thing. The index stores them in dictionaries,
    /// whose iteration order is not stable across runs.
    func names(of kind: ObjCDeclarationKind) -> [String] {
        switch kind {
        case .classes: indexer.classNames.sorted()
        case .protocols: indexer.protocolNames.sorted()
        case .categories: indexer.categoryNames.sorted()
        case .structs: indexer.structNames.sorted()
        case .unions: indexer.unionNames.sorted()
        }
    }

    /// Whether the index holds no declaration at all, of any kind. This is
    /// what separates "this binary carries no Objective-C metadata" from "the
    /// kinds asked for happen to be empty in it" — the two are otherwise
    /// indistinguishable from an empty dump.
    var isEmpty: Bool {
        ObjCDeclarationKind.allCases.allSatisfy { names(of: $0).isEmpty }
    }

    // MARK: - Progress

    private static func reportProgress(_ event: ObjCIndexingEvent, to output: some SwiftSectionOutput) {
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
        output.reportProgress(line)
    }
}

extension MachOSource {
    /// How a diagnostic names the image when the caller did not say: the
    /// cache image's name or path, or the file's path.
    var imageDescription: String {
        switch self {
        case .file(let path, _):
            path
        case .dyldSharedCache(_, .name(let name)), .systemDyldSharedCache(.name(let name)):
            name
        case .dyldSharedCache(_, .path(let path)), .systemDyldSharedCache(.path(let path)):
            path
        }
    }
}
