import Foundation
import SwiftSyntax
import SwiftParser

/// Scans a directory of Swift source files and extracts the set of public/open
/// `func`, `var`, `init`, and `subscript` members, keyed by `(typeName, memberName)`.
///
/// Skipped:
/// - `internal`, `private`, `fileprivate` declarations
/// - `@_spi(...)` declarations (treated as non-public)
/// - members on types named exactly `Layout` (the nested record struct used
///   by `*Descriptor`/`*Metadata` wrappers — exercised via parent's tests
///   and `LayoutTests` rather than standalone Suites). Top-level types
///   whose name happens to end with `Layout` (e.g., `TypeLayout`) are NOT
///   filtered.
/// - `init(layout:offset:)` synthesized by `@MemberwiseInit`
/// - extensions on enums whose name ends with `Kind`/`Flags` and similar pure-data utilities
///   (handled via allowlist if they slip through)
///
/// Identifier normalization: backtick-quoted identifiers (e.g.,
/// `` `Protocol` ``, `` `protocol` ``) appear without the backticks in
/// emitted MethodKeys so they align with `Suite.testedTypeName` /
/// `registeredTestMethodNames` (which are plain Strings).
package struct PublicMemberScanner {
    package let sourceRoot: URL

    package init(sourceRoot: URL) {
        self.sourceRoot = sourceRoot
    }

    package func scan(applyingAllowlist allowlist: Set<MethodKey> = []) throws -> Set<MethodKey> {
        let files = try collectSwiftFiles(under: sourceRoot)
        var result: Set<MethodKey> = []
        for fileURL in files {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let tree = Parser.parse(source: source)
            let visitor = PublicMemberVisitor(viewMode: .sourceAccurate)
            visitor.walk(tree)
            for key in visitor.collected {
                if allowlist.contains(key) { continue }
                result.insert(key)
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

private final class PublicMemberVisitor: SyntaxVisitor {
    private(set) var collected: [MethodKey] = []
    private var typeStack: [String] = []
    /// Tracks `@_spi(...)` status of each enclosing scope. A member is SPI if its
    /// own attributes carry `@_spi`, OR any enclosing extension/type does.
    private var spiStack: [Bool] = []

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(stripBackticks(node.name.text))
        spiStack.append(hasSPI(attributes: node.attributes))
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) {
        typeStack.removeLast()
        spiStack.removeLast()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(stripBackticks(node.name.text))
        spiStack.append(hasSPI(attributes: node.attributes))
        return .visitChildren
    }
    override func visitPost(_ node: StructDeclSyntax) {
        typeStack.removeLast()
        spiStack.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(stripBackticks(node.name.text))
        spiStack.append(hasSPI(attributes: node.attributes))
        return .visitChildren
    }
    override func visitPost(_ node: EnumDeclSyntax) {
        typeStack.removeLast()
        spiStack.removeLast()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(stripBackticks(node.name.text))
        spiStack.append(hasSPI(attributes: node.attributes))
        return .visitChildren
    }
    override func visitPost(_ node: ProtocolDeclSyntax) {
        typeStack.removeLast()
        spiStack.removeLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Push the extended type as the current scope. Strip surrounding
        // backticks so identifiers like `extension `Protocol`` resolve to
        // the same MethodKey typeName ("Protocol") that Suites declare via
        // their `testedTypeName: String` constants.
        typeStack.append(stripBackticks(node.extendedType.trimmedDescription))
        spiStack.append(hasSPI(attributes: node.attributes))
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) {
        typeStack.removeLast()
        spiStack.removeLast()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isPublicLike(node.modifiers, attributes: node.attributes) else { return .skipChildren }
        guard let typeName = currentTypeName() else { return .skipChildren }
        if shouldSkip(typeName: typeName) { return .skipChildren }
        collected.append(MethodKey(typeName: typeName, memberName: stripBackticks(node.name.text)))
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isPublicLike(node.modifiers, attributes: node.attributes) else { return .skipChildren }
        guard let typeName = currentTypeName() else { return .skipChildren }
        if shouldSkip(typeName: typeName) { return .skipChildren }
        for binding in node.bindings {
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                collected.append(MethodKey(typeName: typeName, memberName: stripBackticks(pattern.identifier.text)))
            }
        }
        return .skipChildren
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isPublicLike(node.modifiers, attributes: node.attributes) else { return .skipChildren }
        guard let typeName = currentTypeName() else { return .skipChildren }
        if shouldSkip(typeName: typeName) { return .skipChildren }
        if isMemberwiseSynthesizedInit(node) { return .skipChildren }
        let signature = node.signature.parameterClause.parameters.map { $0.firstName.text }.joined(separator: ":")
        let memberName = signature.isEmpty ? "init" : "init(\(signature):)"
        collected.append(MethodKey(typeName: typeName, memberName: memberName))
        return .skipChildren
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isPublicLike(node.modifiers, attributes: node.attributes) else { return .skipChildren }
        guard let typeName = currentTypeName() else { return .skipChildren }
        if shouldSkip(typeName: typeName) { return .skipChildren }
        let signature = node.parameterClause.parameters.map { $0.firstName.text }.joined(separator: ":")
        let memberName = signature.isEmpty ? "subscript" : "subscript(\(signature):)"
        collected.append(MethodKey(typeName: typeName, memberName: memberName))
        return .skipChildren
    }

    private func currentTypeName() -> String? {
        typeStack.last
    }

    private func shouldSkip(typeName: String) -> Bool {
        // Skip the nested `Layout` struct used by `*Descriptor`/`*Metadata`
        // wrappers (e.g., `StructDescriptor.Layout`). Those record types
        // intentionally project raw on-disk fields and are exercised via
        // their parent's tests, not as standalone Suites.
        //
        // We deliberately match only the nested name (after typeStack
        // resolution returns the immediate enclosing identifier "Layout"),
        // NOT every type whose name happens to end with "Layout". A
        // top-level type like `TypeLayout` is a real public API surface
        // with its own Suite, so it must NOT be filtered here.
        if typeName == "Layout" { return true }
        return false
    }

    private func isPublicLike(_ modifiers: DeclModifierListSyntax, attributes: AttributeListSyntax) -> Bool {
        // Reject if any @_spi attribute is present on the member itself,
        // or on any enclosing extension/type scope.
        if hasSPI(attributes: attributes) { return false }
        if spiStack.contains(true) { return false }
        // Accept only if `public` or `open` modifier exists.
        for modifier in modifiers {
            let name = modifier.name.text
            if name == "public" || name == "open" { return true }
        }
        return false
    }

    private func hasSPI(attributes: AttributeListSyntax) -> Bool {
        for attribute in attributes {
            if let attr = attribute.as(AttributeSyntax.self),
               attr.attributeName.trimmedDescription == "_spi" {
                return true
            }
        }
        return false
    }

    private func isMemberwiseSynthesizedInit(_ node: InitializerDeclSyntax) -> Bool {
        // Detect explicit synthesis when authoring class declares @MemberwiseInit;
        // the macro expands to init(layout: ..., offset: ...).
        let names = node.signature.parameterClause.parameters.map { $0.firstName.text }
        return names == ["layout", "offset"] || names == ["offset", "layout"]
    }

    /// Identifiers that collide with Swift keywords (e.g., `protocol`,
    /// `Protocol`) appear in source as backtick-quoted (`` `protocol` ``). The
    /// token text retains those backticks; strip them so MethodKey lookups
    /// align with the unquoted form Suites use in `testedTypeName` /
    /// `registeredTestMethodNames`.
    private func stripBackticks(_ identifier: String) -> String {
        var stripped = identifier
        if stripped.hasPrefix("`") { stripped.removeFirst() }
        if stripped.hasSuffix("`") { stripped.removeLast() }
        return stripped
    }
}
