import SwiftDeclaration
import Demangling
import Utilities

/// The slice of printer state the declaration layer writes.
///
/// Both properties are read by the type layers (`isProtocol` by
/// `DependentGenericNodePrintable`, `targetNode` by `TypeNodePrintable`) and
/// set exactly once per `printRoot`, here, when the unwrapping walk reaches
/// the declaration node.
protocol MemberDeclarationNodePrintableContext: NodePrintableContext {
    var isProtocol: Bool { get set }
    var targetNode: Node? { get set }
}

/// A printer for one member declaration: a variable, a subscript or a function.
///
/// The three differ only in the declaration node kinds they accept and in the
/// body they print for one (`let x: T`, `subscript(...) -> T`, `func f(...)`).
/// Everything around that body is the same — the `final` / `override` /
/// `static` modifiers, the walk from the `global` root down through the
/// wrappers a symbol carries (`static`, `methodDescriptor`, `protocolWitness`,
/// an accessor) to the declaration itself, recording the declaration for the
/// opaque-type lookup and detecting a protocol context, the `where` clause and
/// the `{ get set }` block — and lives here as default implementations, the
/// way the type layers below share theirs.
protocol MemberDeclarationNodePrintable: InterfaceNodePrintable where Context: MemberDeclarationNodePrintableContext {
    var isFinal: Bool { get }
    var isOverride: Bool { get }
    /// `static` members of a class print as `class` when the member is
    /// overridable (a vtable slot exists for it).
    var isClassMember: Bool { get }

    /// The node kinds the walk stops at and hands to `printDeclaration(_:)`.
    static var declarationNodeKinds: Set<Node.Kind> { get }

    /// Prints the declaration itself. `enterDeclaration(_:isStatic:)` has
    /// already run: `context.targetNode` and `context.isProtocol` are set.
    mutating func printDeclaration(_ node: Node) async throws
}

enum MemberDeclarationPrintError: Swift.Error {
    /// The walk reached a node that is neither a wrapper it knows nor one of
    /// the printer's `declarationNodeKinds`.
    case unsupportedNode(Node, expected: Set<Node.Kind>)
    /// A declaration node with neither an `identifier` nor a `privateDeclName`.
    case missingIdentifier(Node)
}

extension MemberDeclarationNodePrintable {
    /// Wrappers a `global` may carry in front of the entity; the entity is then
    /// the second child.
    static var skippedGlobalWrapperKinds: Set<Node.Kind> {
        [
            .asyncFunctionPointer,
            .asyncSuspendResumePartialFunction,
            .mergedFunction,
        ]
    }

    mutating func printRoot(_ node: Node) async throws -> Target {
        if isFinal {
            target.write("final", context: .context(state: .printKeyword))
            target.writeSpace()
        }
        if isOverride {
            target.write("override", context: .context(state: .printKeyword))
            target.writeSpace()
        }
        try await unwrapAndPrintDeclaration(node, isStatic: false)
        return target
    }

    /// Walks from a symbol's root to its declaration node. `isStatic` is set
    /// once a `static` wrapper has been passed and is consumed by
    /// `enterDeclaration(_:isStatic:)`; it has no life beyond this walk.
    private mutating func unwrapAndPrintDeclaration(_ node: Node, isStatic: Bool) async throws {
        if Self.declarationNodeKinds.contains(node.kind) {
            enterDeclaration(node, isStatic: isStatic)
            try await printDeclaration(node)
        } else if node.kind == .global, let first = node.children.first {
            if Self.skippedGlobalWrapperKinds.contains(first.kind), let second = node.children.second {
                try await unwrapAndPrintDeclaration(second, isStatic: isStatic)
            } else {
                try await unwrapAndPrintDeclaration(first, isStatic: isStatic)
            }
        } else if node.kind == .static, let first = node.children.first {
            target.write(isClassMember ? "class" : "static", context: .context(state: .printKeyword))
            target.writeSpace()
            try await unwrapAndPrintDeclaration(first, isStatic: true)
        } else if node.kind == .methodDescriptor || node.kind == .getter || node.kind == .setter, let first = node.children.first {
            try await unwrapAndPrintDeclaration(first, isStatic: isStatic)
        } else if node.kind == .protocolWitness, let second = node.children.second {
            try await unwrapAndPrintDeclaration(second, isStatic: isStatic)
        } else {
            throw MemberDeclarationPrintError.unsupportedNode(node, expected: Self.declarationNodeKinds)
        }
    }

    /// Records the declaration for the opaque return type lookup — wrapped in
    /// a `static` node again when the symbol had one, because that is the
    /// shape the descriptor index is keyed by — and detects whether it sits in
    /// a protocol or a protocol extension, which is what spells `A` as `Self`.
    ///
    /// Detection looks at the entity inside a `boundGenericFunction`, whose
    /// own first child is the function, not its context.
    mutating func enterDeclaration(_ node: Node, isStatic: Bool) {
        context.targetNode = isStatic ? Node.create(kind: .static, child: node) : node
        let entity = splitBoundGenericFunction(node).entity
        if let first = entity.children.first {
            if first.isKind(of: .extension) {
                context.isProtocol = first.children.at(1)?.isKind(of: .protocol) ?? false
            } else if first.isKind(of: .protocol) {
                context.isProtocol = true
            }
        }
    }

    /// A `boundGenericFunction` carries the function in child 0 and its generic
    /// argument list in child 1; any other node is its own entity.
    func splitBoundGenericFunction(_ node: Node) -> (entity: Node, genericArguments: Node?) {
        if node.kind == .boundGenericFunction, let entity = node.children.at(0), let genericArguments = node.children.at(1) {
            return (entity, genericArguments)
        }
        return (node, nil)
    }

    /// The `where` clause of the declaration's generic signature, if it has
    /// printable requirements.
    mutating func printWhereClause(of node: Node) async {
        guard let genericSignature = node.first(of: .dependentGenericSignature) else { return }
        let requirements = genericSignature.all(of: .printableRequirementKinds)
        for (offset, requirement) in requirements.offsetEnumerated() {
            if offset.isStart {
                target.writeSpace()
                target.write("where", context: .context(state: .printKeyword))
                target.writeSpace()
            }
            await printName(requirement)
            if !offset.isEnd {
                target.write(", ")
            }
        }
    }

    /// The `{ get }` / `{ get set }` block of a computed variable or a
    /// subscript, indented one level deeper than the declaration.
    mutating func printAccessorBlock(hasSetter: Bool, indentation: Int) {
        target.write(" {")
        target.write("\n")
        target.write(String(repeating: " ", count: (indentation + 1) * 4))
        target.write("get", context: .context(state: .printKeyword))
        if hasSetter {
            target.write("\n")
            target.write(String(repeating: " ", count: (indentation + 1) * 4))
            target.write("set", context: .context(state: .printKeyword))
        }
        target.write("\n")
        target.write(String(repeating: " ", count: indentation * 4))
        target.write("}")
    }
}
