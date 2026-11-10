import Foundation
import MachOKit
import ObjCDeclarationRendering
import ObjCOutputTransformer
import OutputTransformer
import Semantic
import SwiftDeclaration
import SwiftIndexing
@_spi(Support) import SwiftInterface
@_spi(Support) import SwiftPrinting

/// `swift-section objc interface`: print the interface of one Objective-C
/// declaration.
public struct ObjCInterfaceRequest: Sendable, Equatable {
    /// A class name (`NSString`), a protocol name (`NSCopying`), a category's
    /// unique name in `ClassName(CategoryName)` form, or a struct or union
    /// name.
    public var declarationName: String
    /// Only look among declarations of this kind; `nil` searches every kind,
    /// in ``ObjCDeclarationKind`` order. Binaries do reuse a name across a
    /// class, a protocol and a struct, and this is how a caller settles it.
    public var kind: ObjCDeclarationKind?
    public var source: MachOSource
    public var generation: ObjCGenerationOptions
    public var cTypeReplacements: [ObjCPrimitiveTypePattern: String]
    /// A custom ivar-offset comment. Giving one turns ivar offset comments on.
    public var ivarOffsetComment: Transformer.ObjCIvarOffset?
    public var reportsIndexingProgress: Bool
    public var destination: ProductDestination
    /// Print the declaration as Swift imports it — names by the
    /// ClangImporter's rules, members Swift implements as their Swift
    /// declarations — instead of as an Objective-C header (evolution
    /// proposal `objc-imported-declarations`). Classes, categories and
    /// protocols only; the header options do not apply.
    public var printsSwiftImport: Bool

    public init(
        declarationName: String,
        kind: ObjCDeclarationKind? = nil,
        source: MachOSource,
        generation: ObjCGenerationOptions = .init(),
        cTypeReplacements: [ObjCPrimitiveTypePattern: String] = [:],
        ivarOffsetComment: Transformer.ObjCIvarOffset? = nil,
        reportsIndexingProgress: Bool = false,
        destination: ProductDestination = .output,
        printsSwiftImport: Bool = false
    ) {
        self.declarationName = declarationName
        self.kind = kind
        self.source = source
        self.generation = generation
        self.cTypeReplacements = cTypeReplacements
        self.ivarOffsetComment = ivarOffsetComment
        self.reportsIndexingProgress = reportsIndexingProgress
        self.destination = destination
        self.printsSwiftImport = printsSwiftImport
    }

    public func run(output: some SwiftSectionOutput) async throws {
        if printsSwiftImport {
            try await runPrintingSwiftImport(output: output)
            return
        }
        let session = try await ObjCInterfaceSession.make(
            source: source,
            generation: generation,
            cTypeReplacements: cTypeReplacements,
            ivarOffsetComment: ivarOffsetComment,
            reportsIndexingProgress: reportsIndexingProgress,
            output: output
        )

        // Searched in declaration-kind order rather than by guessing from the
        // spelling: `Foo(Bar)` is unambiguous, but a bare name could be a
        // class, a protocol or a struct.
        for candidateKind in kind.map({ [$0] }) ?? ObjCDeclarationKind.allCases {
            guard let interface = session.interface(of: candidateKind, named: declarationName) else { continue }
            switch destination {
            case .file(let path):
                try interface.string.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            case .output:
                output.write(.declarations(interface))
            }
            return
        }

        throw ObjCDeclarationLookupError.declarationNotFound(declarationName)
    }

    /// The Swift side: the image's declaration index, which pairs a class or
    /// category Swift implements with its Swift definitions.
    private func runPrintingSwiftImport(output: some SwiftSectionOutput) async throws {
        let machOFile = try source.load()
        let builder = try SwiftInterfaceBuilder(eventHandlers: output.indexEventHandlers(forInputLabeled: nil), in: machOFile)
        output.reportProgress("Indexing Swift declarations...")
        try await builder.prepare()

        for candidateKind in kind.map({ [$0] }) ?? ObjCDeclarationKind.allCases {
            let interface: SemanticString
            switch candidateKind {
            case .classes:
                guard let definition = builder.indexer.objcImportedClassDefinition(named: declarationName) else { continue }
                interface = try await builder.printer.printObjCImportedClassDefinition(definition)
            case .protocols:
                guard let definition = builder.indexer.objcImportedProtocolDefinition(named: declarationName) else { continue }
                interface = try await builder.printer.printObjCImportedProtocolDefinition(definition)
            case .categories:
                guard let definition = builder.indexer.objcImportedCategoryDefinition(uniqueName: declarationName) else { continue }
                interface = try await builder.printer.printObjCImportedCategoryDefinition(definition)
            case .structs, .unions:
                // C aggregates are no Objective-C declarations to import.
                continue
            }
            switch destination {
            case .file(let path):
                try interface.string.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
            case .output:
                output.write(.declarations(interface))
            }
            return
        }

        throw ObjCDeclarationLookupError.declarationNotFound(declarationName)
    }
}

public enum ObjCDeclarationLookupError: Swift.Error, LocalizedError, Sendable, Equatable {
    case declarationNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .declarationNotFound(let name):
            "No class, protocol, category, struct or union named '\(name)' in this binary."
        }
    }
}
