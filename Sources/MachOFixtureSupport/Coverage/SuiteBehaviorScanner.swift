import Foundation
import SwiftSyntax
import SwiftParser

/// Scans `*Tests.swift` Suite source files and reports per-method behavior:
/// whether each `@Test func` calls `acrossAllReaders` / `acrossAllContexts`,
/// `usingInProcessOnly` / `inProcessContext`, or neither.
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

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        currentTestedTypeName = extractTestedTypeName(from: node.memberBlock)
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) {
        currentTestedTypeName = nil
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        currentTestedTypeName = extractTestedTypeName(from: node.memberBlock)
        return .visitChildren
    }
    override func visitPost(_ node: StructDeclSyntax) {
        currentTestedTypeName = nil
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard hasTestAttribute(node.attributes),
              let testedTypeName = currentTestedTypeName,
              let body = node.body else {
            return .skipChildren
        }
        let behavior = inferBehavior(from: body)
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

    private func inferBehavior(from body: CodeBlockSyntax) -> SuiteBehaviorScanner.MethodBehavior {
        let bodyText = body.description
        let crossReaderMarkers = [
            "acrossAllReaders", "acrossAllContexts",
            "machOFile", "machOImage",
            "fileContext", "imageContext",
        ]
        if crossReaderMarkers.contains(where: { bodyText.contains($0) }) {
            return .acrossAllReaders
        }
        let inProcessMarkers = ["usingInProcessOnly", "inProcessContext"]
        if inProcessMarkers.contains(where: { bodyText.contains($0) }) {
            return .inProcessOnly
        }
        return .sentinel
    }
}
