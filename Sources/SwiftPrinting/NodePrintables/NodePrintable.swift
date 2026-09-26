import SwiftDeclaration
import Demangling
import Foundation
import Utilities

/// The slice of printer state one layer reads or writes.
///
/// Each `*NodePrintable` layer refines this with exactly the properties it
/// touches and constrains its `Context` to that refinement, so a layer sees
/// only its own slice; a layer that touches no state at all
/// (`BoundGenericNodePrintable`) declares no refinement. The concrete printer's
/// `Context` satisfies every refinement with one stored property per name, and
/// a name two layers both declare is one property they share. See
/// `InterfaceNodePrinterContext` for the full set, and evolution proposal
/// `node-printer-declaration-layer-and-context-roles` for why the state lives
/// here rather than as nine requirements on the printer itself.
protocol NodePrintableContext {
    /// How many `dependentMemberType` nodes enclose the node being printed.
    /// Inside one, a nominal reference is spelled without its qualifying
    /// context (`A.Element`, not `A.Swift.Sequence.Element`); see
    /// `shouldPrintContext()`.
    var dependentMemberTypeDepth: Int { get }
}

/// Per-call hints for one `printName`.
///
/// These apply to exactly the node handed over and must not reach its
/// children, which is why they travel as a parameter instead of living on
/// `Context`: a function *declaration* prints with `isBlockOrClosure == false`
/// so its `-> ()` is dropped, while a closure type among its parameters keeps
/// `(Int) -> ()` — stored state would hand the flag down to that closure.
struct NodePrintOptions: Equatable {
    /// The node is the qualifying context of another (the `Outer` of
    /// `Outer.Inner`).
    var asPrefixContext = false

    /// The function type belongs to an `init`, whose result is implicit.
    var isAllocator = false

    /// The function type is a block or closure *type*, which always spells its
    /// result; a function declaration omits `-> ()`.
    var isBlockOrClosure = true

    static let `default` = NodePrintOptions()
}

protocol NodePrintable {
    associatedtype Target: NodePrinterTarget

    associatedtype Context: NodePrintableContext

    var target: Target { set get }

    /// The traversal state every layer of this printer shares. Which
    /// properties a layer may read or write is what that layer's
    /// `*NodePrintableContext` refinement declares.
    var context: Context { get set }

    var delegate: NodePrintableDelegate? { get }

    mutating func printName(_ name: Node, options: NodePrintOptions) async
}

extension Sequence where Element == Node.Kind {
    /// The requirement kinds that belong in a printed `where` clause.
    ///
    /// Upstream's `requirementKinds` also lists
    /// `dependentGenericSameShapeRequirement`, which source never writes — it
    /// is implied by the expansion itself (`repeat (each A, each B)`) — and
    /// which upstream renders as `A.shape == B.shape`, not Swift syntax.
    /// Worse, this printer has no case for that node, so including it emitted
    /// a `where ` with nothing after it.
    static var printableRequirementKinds: [Node.Kind] {
        requirementKinds.filter { $0 != .dependentGenericSameShapeRequirement }
    }
}

extension NodePrintable {
    /// Single-path recursion budget, matching ``Swift::Demangle::NodePrinter::MaxDepth``
    /// in ``swift/include/swift/Demangling/Demangle.h``.
    static var maxPrintDepth: Int { 768 }
}

extension NodePrintable {
    mutating func printNameInBase(_ name: Node) async -> Bool {
        switch name.kind {
        case .global:
            await printChildren(name)
        case .module:
            await printModule(name)
        case .identifier:
            await printIdentifier(name)
        case .privateDeclName:
            await printPrivateDeclName(name)
        case .inOut:
            await printFirstChild(name, prefix: "inout ", prefixContext: .context(for: name, state: .printKeyword))
        case .owned:
            // Swift 5.9+ source-level spelling for the `n` ownership mangling.
            // The demangler ABI calls this `Owned`; swift-demangling and the
            // historical Swift NodePrinter both emit `__owned`. We prefer the
            // source-facing keyword `consuming` here.
            await printFirstChild(name, prefix: "consuming ", prefixContext: .context(for: name, state: .printKeyword))
        case .shared:
            // Source-level spelling for the `h` ownership mangling.
            // Demangler kind is `Shared`; older spelling is `__shared`.
            await printFirstChild(name, prefix: "borrowing ", prefixContext: .context(for: name, state: .printKeyword))
        case .isolated:
            await printFirstChild(name, prefix: "isolated ", prefixContext: .context(for: name, state: .printKeyword))
        case .isolatedAnyFunctionType:
            target.write("@isolated(any) ", context: .context(for: name, state: .printKeyword))
        case .dynamicSelf:
            target.write("Self", context: .context(for: name, state: .printKeyword))
        case .integer:
            // SE-0452 value-generic integer (`Foo<5>`, `where count == 5`),
            // mirroring the Demangling `NodePrinter` output.
            target.write("\(name.index ?? 0)")
        case .negativeInteger:
            target.write("-\(name.index ?? 0)")
        case .accessorFunctionReference:
            // Kind-9 symbolic reference: the compiler embedded a pointer to a
            // metadata accessor thunk instead of a demanglable name (emitted
            // when the deployment target's runtime demangler predates the
            // type's mangling, e.g. `~Copyable` generics back-deployed before
            // macOS 15). Offline this is unresolvable by construction — the
            // thunk would have to be executed — so mirror the Demangling
            // `NodePrinter` fallback verbatim; `index` is the thunk's file
            // offset. Previously unhandled, which rendered the node as an
            // empty string and produced `case name()` — invalid Swift.
            target.write("accessor function at \(name.index ?? 0)")
        case .index:
            // The ordinal inside an `opaqueType` node (child 1) — the `.0` in
            // `<<opaque return type of f()>>.0`, which selects WHICH `some` of
            // a multi-opaque return this is. Previously unhandled, so the
            // ordinal vanished and the reference printed with a trailing dot.
            target.write("\(name.index ?? 0)")
        case .opaqueTypeDescriptorSymbolicReference:
            // An opaque type descriptor the rewriter could not expand, still
            // spelled as a POINTER (the shared-cache case; the standalone-file
            // case is `.opaqueReturnTypeOf` instead). Offline-unresolvable by
            // construction once expansion has failed, so mirror the Demangling
            // `NodePrinter` fallback verbatim — same reasoning as
            // `accessorFunctionReference` above. `hexadecimalString` upstream
            // is internal; this is its definition.
            target.write("opaque type symbolic reference 0x\(String(name.index ?? 0, radix: 16, uppercase: true))")
        default:
            return false
        }
        return true
    }

    /// Whether a nominal reference spells its qualifying context. It does not
    /// inside a `dependentMemberType` chain, where the leaf stands alone.
    func shouldPrintContext() -> Bool {
        context.dependentMemberTypeDepth == 0
    }

    /// Returns whether a C-imported module spelling (`__C` / `__ObjC`) was
    /// resolved to its real module — the caller uses that to decide whether
    /// the sibling identifier may be rewritten to its Swift spelling too.
    @discardableResult
    mutating func printModule(_ node: Node, siblingIdentifier: String? = nil) async -> Bool {
        var moduleName = node.text ?? ""
        var resolvedCImportedModule = false
        if moduleName == objcModule || moduleName == cModule,
           let identifier = siblingIdentifier,
           let delegate,
           let updatedModuleName = await or(await delegate.moduleName(forTypeName: identifier), await delegate.moduleName(forTypeName: identifier.strippedRefSuffix)) {
            moduleName = updatedModuleName
            resolvedCImportedModule = true
        }
        target.write(moduleName, context: .context(for: node, state: .printModule))
        return resolvedCImportedModule
    }

    mutating func printIdentifier(_ node: Node, parentKind: Node.Kind? = nil) async {
        target.write(node.text ?? "", context: .context(for: node, parentKind: parentKind, state: .printIdentifier))
    }

    mutating func printPrivateDeclName(_ node: Node, parentKind: Node.Kind? = nil) async {
        guard let child = node.children.at(1) else { return }
        await printIdentifier(child, parentKind: parentKind)
    }

    mutating func printName(_ name: Node) async {
        await printName(name, options: .default)
    }

    mutating func printOptional(_ optional: Node?, prefix: String? = nil, prefixContext: NodePrintContext? = nil, suffix: String? = nil, suffixContext: NodePrintContext? = nil, asPrefixContext: Bool = false) async {
        guard let node = optional else { return }
        prefix.map { target.write($0, context: prefixContext) }
        await printName(node, options: NodePrintOptions(asPrefixContext: asPrefixContext))
        suffix.map { target.write($0, context: suffixContext) }
    }

    mutating func printFirstChild(_ ofName: Node, prefix: String? = nil, prefixContext: NodePrintContext? = nil, suffix: String? = nil, suffixContext: NodePrintContext? = nil, asPrefixContext: Bool = false) async {
        await printOptional(ofName.children.at(0), prefix: prefix, prefixContext: prefixContext, suffix: suffix, suffixContext: suffixContext, asPrefixContext: asPrefixContext)
    }

    mutating func printSequence<Nodes: Sequence>(_ names: Nodes, prefix: String? = nil, prefixContext: NodePrintContext? = nil, suffix: String? = nil, suffixContext: NodePrintContext? = nil, separator: String? = nil) async where Nodes.Element == Node {
        var isFirst = true
        prefix.map { target.write($0, context: prefixContext) }
        for node in names {
            if let separator, !isFirst {
                target.write(separator)
            } else {
                isFirst = false
            }
            await printName(node)
        }
        suffix.map { target.write($0, context: suffixContext) }
    }

    mutating func printChildren(_ ofName: Node, prefix: String? = nil, prefixContext: NodePrintContext? = nil, suffix: String? = nil, suffixContext: NodePrintContext? = nil, separator: String? = nil) async {
        await printSequence(ofName.children, prefix: prefix, prefixContext: prefixContext, suffix: suffix, suffixContext: suffixContext, separator: separator)
    }
}

extension String {
    fileprivate var strippedRefSuffix: String {
        if hasSuffix("Ref") {
            return String(dropLast(3))
        }
        return self
    }
}
