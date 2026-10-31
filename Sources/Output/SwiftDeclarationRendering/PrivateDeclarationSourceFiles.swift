import Demangling
import SwiftInspection

/// The source file a private discriminator was derived from, as dump and
/// interface name it (evolution proposal `private-declaration-source-files`).
public struct PrivateDeclarationSourceFile: Hashable, Sendable {
    /// The file's name, `Enabled.swift`.
    public let fileName: String

    /// The module name that went into the discriminator: a framework's own
    /// name (`SwiftUICore`), which is not always the module its declarations
    /// print under (`SwiftUI`).
    public let moduleName: String

    /// Whether the discriminator belongs to the file the compiler synthesizes
    /// for `fileName`, not to `fileName` itself.
    public let isSynthesized: Bool

    public init(fileName: String, moduleName: String, isSynthesized: Bool) {
        self.fileName = fileName
        self.moduleName = moduleName
        self.isSynthesized = isSynthesized
    }
}

/// What tells dump and interface the source file of a private discriminator
/// (evolution proposal `private-declaration-source-files`). The library's own
/// is `SwiftPrivateDiscriminators`' `PrivateDiscriminatorSourceFileIndex`,
/// which sits above this module.
///
/// It is asked once for every private declaration printed, from the printing
/// thread, so an answer should cost a lookup: search for the whole image
/// before printing.
public protocol PrivateDeclarationSourceFileProviding: Sendable {
    /// The source file `discriminator` was derived from; `nil` when it could
    /// not be recovered.
    func sourceFile(forPrivateDiscriminator discriminator: String) -> PrivateDeclarationSourceFile?
}

/// The comments above a printed declaration that name the source files its
/// private declarations come from (evolution proposal
/// `private-declaration-source-files`). Dump and interface print the same
/// lines.
package enum PrivateDeclarationSourceFileComments {
    /// One line for each discriminator the names in `nodes` read that
    /// `enclosingNodes` — the names of the declaration they are printed inside,
    /// a conformance's type and protocol — do not, in the order the names read
    /// them.
    ///
    /// A type nested in a private type, or a member of one, is necessarily
    /// declared in that type's file, so it repeats nothing; a private member of
    /// a public type says where it is. A line names the last declaration read
    /// with its discriminator: the private type `B` in `(A in _X).(B in _X)`.
    package static func lines(
        for nodes: [any DemanglingNode],
        enclosedBy enclosingNodes: [any DemanglingNode],
        provider: any PrivateDeclarationSourceFileProviding
    ) -> [String] {
        lineBodies(for: nodes, enclosedBy: enclosingNodes, provider: provider).map(\.text)
    }

    /// `lines(for:enclosedBy:provider:)` as the comments the printers emit.
    package static func comments(
        for nodes: [any DemanglingNode],
        enclosedBy enclosingNodes: [any DemanglingNode],
        provider: any PrivateDeclarationSourceFileProviding
    ) -> [StructuredComment] {
        lineBodies(for: nodes, enclosedBy: enclosingNodes, provider: provider).map(StructuredComment.line)
    }

    private static func lineBodies(
        for nodes: [any DemanglingNode],
        enclosedBy enclosingNodes: [any DemanglingNode],
        provider: any PrivateDeclarationSourceFileProviding
    ) -> [[StructuredComment.Segment]] {
        let enclosingDiscriminators = Set(enclosingNodes.flatMap { $0.privateDeclarations.map(\.discriminator) })
        var discriminators: [String] = []
        var lastDeclarationByDiscriminator: [String: (declaration: PrivateDeclaration, moduleName: String?)] = [:]
        for node in nodes {
            let moduleName = declaringModuleName(of: node)
            for privateDeclaration in node.privateDeclarations where !enclosingDiscriminators.contains(privateDeclaration.discriminator) {
                if lastDeclarationByDiscriminator[privateDeclaration.discriminator] == nil {
                    discriminators.append(privateDeclaration.discriminator)
                }
                lastDeclarationByDiscriminator[privateDeclaration.discriminator] = (privateDeclaration, moduleName)
            }
        }
        return discriminators.compactMap { discriminator in
            lastDeclarationByDiscriminator[discriminator].map { lineBody(for: $0.declaration, sourceFile: provider.sourceFile(forPrivateDiscriminator: discriminator), printedModuleName: $0.moduleName) }
        }
    }

    /// The line saying where `privateDeclaration` is declared:
    /// `EnabledKey is declared in Enabled.swift of module SwiftUICore`, the
    /// module named only when it is not the one the declaration prints under.
    /// One nothing recovered says so, with its discriminator: the interface
    /// prints none anywhere else.
    package static func line(for privateDeclaration: PrivateDeclaration, sourceFile: PrivateDeclarationSourceFile?, printedModuleName: String?) -> String {
        lineBody(for: privateDeclaration, sourceFile: sourceFile, printedModuleName: printedModuleName).text
    }

    /// `line(for:sourceFile:printedModuleName:)` as segments: the
    /// declaration's name, the file's and the module's (evolution proposal
    /// `comment-structure`).
    package static func lineBody(for privateDeclaration: PrivateDeclaration, sourceFile: PrivateDeclarationSourceFile?, printedModuleName: String?) -> [StructuredComment.Segment] {
        var body: [StructuredComment.Segment] = []
        let predicate: String
        if let name = privateDeclaration.name {
            body += [.name(name), .separator(" ")]
            predicate = "is declared in"
        } else {
            predicate = "Declared in"
        }
        guard let sourceFile else {
            return body + [
                .text("\(predicate) a source file whose name could not be recovered"), .separator(" ("),
                .key("private discriminator"), .separator(" "), .value(privateDeclaration.discriminator), .separator(")"),
            ]
        }
        if sourceFile.isSynthesized {
            body += [.text("\(predicate) the file the compiler synthesized for"), .separator(" "), .value(sourceFile.fileName)]
        } else {
            body += [.text(predicate), .separator(" "), .value(sourceFile.fileName)]
        }
        if sourceFile.moduleName != printedModuleName {
            body += [.separator(" "), .text("of module"), .separator(" "), .name(sourceFile.moduleName)]
        }
        return body
    }

    /// The module a name is declared in: the end of its chain of contexts,
    /// each the first child of the one before — an extension's own module
    /// rather than the extended type's.
    private static func declaringModuleName<DeclarationNode: DemanglingNode>(of node: DeclarationNode) -> String? {
        var context: DeclarationNode? = node
        while let currentContext = context {
            if currentContext.kind == .module {
                return currentContext.text
            }
            context = currentContext.children.first
        }
        return nil
    }
}
