import Foundation
import SwiftSyntax
import SwiftParser

/// Scans `*Tests.swift` Suite source files and reports per-method behavior:
/// whether each `@Test func` exercises any reader/context machinery, only
/// touches the in-process context, or is a pure registration-only sentinel.
///
/// Classification rules (applied in order):
///
///   1. If the `@Test func` body itself references any reader/context
///      identifier (`acrossAllReaders`, `acrossAllContexts`, `machOFile`,
///      `machOImage`, `fileContext`, `imageContext`) → `.acrossAllReaders`.
///   2. Otherwise, if the body explicitly uses `usingInProcessOnly` or
///      `inProcessContext` → `.inProcessOnly`.
///   3. Otherwise, fall back to the *enclosing class body*: if the entire
///      class references any cross-reader identifier (typically through a
///      private helper like `loadStructTestMetadata()` that the test calls),
///      treat the method as `.acrossAllReaders` because the helper-call
///      pattern means the test transitively exercises the reader. If only
///      `usingInProcessOnly` / `inProcessContext` shows up class-wide, treat
///      it as `.inProcessOnly`.
///   4. Bodies and classes with none of those markers classify as
///      `.sentinel` (registration-only / synthetic memberwise tests).
///
/// Used by `MachOSwiftSectionCoverageInvariantTests` to enforce that every
/// sentinel-only method is declared in `CoverageAllowlistEntries`.
package struct SuiteBehaviorScanner {
    package enum MethodBehavior: Equatable {
        case acrossAllReaders
        case inProcessOnly
        case sentinel
    }

    package let suiteRoot: URL

    package init(suiteRoot: URL) {
        self.suiteRoot = suiteRoot
    }

    package func scan() throws -> [MethodKey: MethodBehavior] {
        let files = try collectSwiftFiles(under: suiteRoot)
        var result: [MethodKey: MethodBehavior] = [:]
        for fileURL in files {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let tree = Parser.parse(source: source)
            let visitor = SuiteBehaviorVisitor(viewMode: .sourceAccurate)
            visitor.walk(tree)
            for entry in visitor.collected {
                let key = MethodKey(typeName: entry.testedTypeName, memberName: entry.methodName)
                result[key] = entry.behavior
            }
        }
        return result
    }

    private func collectSwiftFiles(under root: URL) throws -> [URL] {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { files.append(url) }
        }
        return files
    }
}

private final class SuiteBehaviorVisitor: SyntaxVisitor {
    struct Entry {
        let testedTypeName: String
        let methodName: String
        let behavior: SuiteBehaviorScanner.MethodBehavior
    }
    private(set) var collected: [Entry] = []
    private var currentTestedTypeName: String?
    /// The serialized text of the enclosing class/struct member block, used
    /// as a fallback when the immediate `@Test func` body has no reader
    /// markers (the test typically calls a private helper that does).
    private var currentEnclosingClassBodyText: String?

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        currentTestedTypeName = extractTestedTypeName(from: node.memberBlock)
        currentEnclosingClassBodyText = node.memberBlock.description
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) {
        currentTestedTypeName = nil
        currentEnclosingClassBodyText = nil
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        currentTestedTypeName = extractTestedTypeName(from: node.memberBlock)
        currentEnclosingClassBodyText = node.memberBlock.description
        return .visitChildren
    }
    override func visitPost(_ node: StructDeclSyntax) {
        currentTestedTypeName = nil
        currentEnclosingClassBodyText = nil
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard hasTestAttribute(node.attributes),
              let testedTypeName = currentTestedTypeName,
              let body = node.body else {
            return .skipChildren
        }
        let behavior = inferBehavior(
            fromBody: body,
            enclosingClassBodyText: currentEnclosingClassBodyText
        )
        collected.append(Entry(
            testedTypeName: testedTypeName,
            methodName: node.name.text,
            behavior: behavior
        ))
        return .skipChildren
    }

    private func extractTestedTypeName(from memberBlock: MemberBlockSyntax) -> String? {
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let isStatic = varDecl.modifiers.contains(where: { $0.name.text == "static" })
            guard isStatic else { continue }
            for binding in varDecl.bindings {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                      pattern.identifier.text == "testedTypeName",
                      let initializer = binding.initializer,
                      let stringLit = initializer.value.as(StringLiteralExprSyntax.self)
                else { continue }
                let value = stringLit.segments.compactMap {
                    $0.as(StringSegmentSyntax.self)?.content.text
                }.joined()
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    private func hasTestAttribute(_ attributes: AttributeListSyntax) -> Bool {
        for attribute in attributes {
            if let attr = attribute.as(AttributeSyntax.self),
               attr.attributeName.trimmedDescription == "Test" {
                return true
            }
        }
        return false
    }

    private static let crossReaderMarkers = [
        "acrossAllReaders", "acrossAllContexts",
        "machOFile", "machOImage",
        "fileContext", "imageContext",
    ]
    private static let inProcessMarkers = ["usingInProcessOnly", "inProcessContext"]

    private func inferBehavior(
        fromBody body: CodeBlockSyntax,
        enclosingClassBodyText: String?
    ) -> SuiteBehaviorScanner.MethodBehavior {
        let bodyText = body.description
        if Self.crossReaderMarkers.contains(where: { bodyText.contains($0) }) {
            return .acrossAllReaders
        }
        if Self.inProcessMarkers.contains(where: { bodyText.contains($0) }) {
            return .inProcessOnly
        }
        // Fall back to the enclosing class body. Tests frequently call a
        // private helper (e.g. `loadStructTestMetadata()`) whose body is the
        // only place the reader is referenced; the @Test func body itself
        // contains no reader marker. Treat the test as `.acrossAllReaders`
        // when the enclosing class as a whole references reader markers.
        if let enclosingText = enclosingClassBodyText {
            if Self.crossReaderMarkers.contains(where: { enclosingText.contains($0) }) {
                return .acrossAllReaders
            }
            if Self.inProcessMarkers.contains(where: { enclosingText.contains($0) }) {
                return .inProcessOnly
            }
        }
        return .sentinel
    }
}
