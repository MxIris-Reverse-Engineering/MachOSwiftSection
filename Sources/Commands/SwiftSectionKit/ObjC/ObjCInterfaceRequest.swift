import Foundation
import ObjCDeclarationRendering
import ObjCOutputTransformer
import OutputTransformer

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

    public init(
        declarationName: String,
        kind: ObjCDeclarationKind? = nil,
        source: MachOSource,
        generation: ObjCGenerationOptions = .init(),
        cTypeReplacements: [ObjCPrimitiveTypePattern: String] = [:],
        ivarOffsetComment: Transformer.ObjCIvarOffset? = nil,
        reportsIndexingProgress: Bool = false,
        destination: ProductDestination = .output
    ) {
        self.declarationName = declarationName
        self.kind = kind
        self.source = source
        self.generation = generation
        self.cTypeReplacements = cTypeReplacements
        self.ivarOffsetComment = ivarOffsetComment
        self.reportsIndexingProgress = reportsIndexingProgress
        self.destination = destination
    }

    public func run(output: some SwiftSectionOutput) async throws {
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
}

public enum ObjCDeclarationLookupError: Error, LocalizedError, Sendable, Equatable {
    case declarationNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .declarationNotFound(let name):
            "No class, protocol, category, struct or union named '\(name)' in this binary."
        }
    }
}
