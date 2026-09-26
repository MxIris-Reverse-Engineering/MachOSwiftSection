import SwiftDeclaration
import Demangling

/// The slice of printer state the dependent-generic layer reads and writes.
protocol DependentGenericNodePrintableContext: NodePrintableContext {
    /// The declaration belongs to a protocol, so generic parameter `A` is
    /// spelled `Self`. Read here, set by the declaration layer.
    var isProtocol: Bool { get }
    var dependentMemberTypeDepth: Int { get set }
    var packExpansionDepth: Int { get }
    var knownPackParameterNames: Set<String> { get set }
}

protocol DependentGenericNodePrintable: NodePrintable where Context: DependentGenericNodePrintableContext {
    mutating func printNameInDependentGeneric(_ name: Node) async -> Bool
    mutating func printGenericSignature(_ name: Node, enclosingGenericType: Node?) async
    mutating func printDependentGenericConformanceRequirement(_ name: Node) async
    mutating func printDependentGenericLayoutRequirement(_ name: Node) async
    mutating func printDependentAssociatedTypeRef(_ name: Node) async
    mutating func printDependentGenericParamType(_ name: Node) async
    mutating func printDependentGenericSameTypeRequirement(_ name: Node) async
    mutating func printDependentGenericType(_ name: Node) async
    mutating func printDependentMemberType(_ name: Node) async
    mutating func printDependentGenericInverseConformanceRequirement(_ name: Node) async
    mutating func printDependentGenericParamName(_ name: String) async
}

extension DependentGenericNodePrintable {
    mutating func printNameInDependentGeneric(_ name: Node) async -> Bool {
        switch name.kind {
        case .dependentGenericParamType:
            await printDependentGenericParamType(name)
        case .dependentAssociatedTypeRef:
            await printDependentAssociatedTypeRef(name)
        case .dependentGenericConformanceRequirement:
            await printDependentGenericConformanceRequirement(name)
        case .dependentGenericLayoutRequirement:
            await printDependentGenericLayoutRequirement(name)
        case .dependentGenericSameTypeRequirement:
            await printDependentGenericSameTypeRequirement(name)
        case .dependentGenericType:
            await printDependentGenericType(name)
        case .dependentMemberType:
            await printDependentMemberType(name)
        case .dependentGenericSignature:
            await printGenericSignature(name, enclosingGenericType: nil)
        case .dependentGenericInverseConformanceRequirement:
            await printDependentGenericInverseConformanceRequirement(name)
        case .dependentGenericParamPackMarker:
            break
        default:
            return false
        }
        return true
    }

    mutating func printDependentAssociatedTypeRef(_ name: Node) async {
        // Drop the protocol qualifier and print only the associated-type identifier.
        // The default demangler form prefixes each segment with the owning protocol,
        // producing chains like `A.OuterProtocol.Middle.MiddleProtocol.Leaf`. Swift
        // source uses the simpler `A.Middle.Leaf`. The ambiguous case (same name on
        // multiple protocols) would need generic-signature disambiguation; left for
        // a future pass.
        await printFirstChild(name)
    }

    mutating func printDependentGenericParamType(_ name: Node) async {
        // Inside a `repeat` pattern, a parameter known to be a pack is spelled
        // `each A` in source. Parenthesized unconditionally — see
        // `printPackExpansion` for why a bare `each` is rejected after a suffix.
        if context.packExpansionDepth > 0, let text = name.text, context.knownPackParameterNames.contains(text) {
            target.write("(")
            target.write("each", context: .context(for: name, state: .printKeyword))
            target.writeSpace()
            await printDependentGenericParamName(text)
            target.write(")")
            return
        }
        await printDependentGenericParamName(name.text ?? "")
    }

    mutating func printDependentGenericParamName(_ name: String) async {
        if context.isProtocol, name == "A" {
            target.write("Self", context: .context(state: .printKeyword))
        } else {
            target.write(name)
        }
    }

    mutating func printGenericSignature(_ name: Node, enclosingGenericType: Node? = nil) async {
        var genericParameterDepthCount = 0
        for child in name.children {
            guard child.kind == .dependentGenericParamCount else { break }
            genericParameterDepthCount += 1
        }

        // A signature that introduces no parameters of its own has nothing to
        // bracket. An extension member whose parameters all belong to the
        // extended type arrives here with every count at zero, and bracketing
        // it unconditionally (as upstream's `NodePrinter` does — correct for a
        // debug demangle) yields `init<>(windowID: String) where ...`, which
        // does not compile. 122 occurrences in SwiftUI; the dump path never
        // reaches this code, so it showed none of them.
        let declaredParameterCount = (0 ..< genericParameterDepthCount).reduce(into: 0) { total, depth in
            total += Int(name.children.at(depth)?.index ?? 0)
        }
        guard declaredParameterCount > 0 else { return }

        target.write("<")
        var firstRequirement = genericParameterDepthCount
        for var child in name.children.dropFirst(genericParameterDepthCount) {
            if child.kind == .type {
                child = child.children.first ?? child
            }
            guard child.kind == .dependentGenericParamPackMarker || child.kind == .dependentGenericParamValueMarker else {
                break
            }
            firstRequirement += 1
        }

        let isGenericParamPack = { (depth: UInt64, index: UInt64) -> Bool in
            for var child in name.children.dropFirst(genericParameterDepthCount).prefix(firstRequirement) {
                guard child.kind == .dependentGenericParamPackMarker else { continue }

                child = child.children.first ?? child
                guard child.kind == .type else { continue }

                child = child.children.first ?? child
                guard child.kind == .dependentGenericParamType else { continue }

                // `dependentGenericParamType`'s children are (depth, index) in
                // that order. Comparing them the other way round matched only
                // when depth == index, which is every parameter of a top-level
                // generic and none of a nested one — so a pack parameter of a
                // method on a generic type (depth 1, index 0) lost its `each`
                // and printed `<A1>` beside a `repeat (each A1)` use site.
                if depth == child.children.at(0)?.index, index == child.children.at(1)?.index {
                    return true
                }
            }

            return false
        }

        let isGenericParamValue = { (depth: UInt64, index: UInt64) -> Node? in
            for var child in name.children.dropFirst(genericParameterDepthCount).prefix(firstRequirement) {
                guard child.kind == .dependentGenericParamValueMarker else { continue }
                child = child.children.first ?? child

                guard child.kind == .type else { continue }

                guard
                    let param = child.children.at(0),
                    let type = child.children.at(1),
                    param.kind == .dependentGenericParamType
                else {
                    continue
                }

                // Same (depth, index) ordering as `isGenericParamPack` above.
                if depth == param.children.at(0)?.index, index == param.children.at(1)?.index {
                    return type
                }
            }

            return nil
        }

        let depths = enclosingGenericType?.findGenericParamsDepth()

        for countNodePosition in 0 ..< genericParameterDepthCount {
            if countNodePosition != 0 {
                target.write("><")
            }

            guard let count = name.children.at(countNodePosition)?.index else { continue }
            for index in 0 ..< count {
                if index != 0 {
                    target.write(", ")
                }

                // Limit the number of printed generic parameters. In practice this
                // it will never be exceeded. The limit is only important for malformed
                // symbols where count can be really huge.
                if index >= 128 {
                    target.write("...")
                    break
                }

                // The loop variable is the position of the parameter-COUNT node,
                // not the parameter's depth — a method on a generic type has
                // one count node while its own parameters live at depth 1. The
                // name already resolves the real depth through `depths`; the
                // pack and value lookups must use the same one, or a nested
                // pack parameter gets looked up at depth 0, comes back "not a
                // pack", and prints `<A1>` right next to its own
                // `repeat (each A1)` use site.
                let resolvedDepth = depths?[index.cast()] ?? countNodePosition.cast()

                let parameterName = genericParameterName(depth: resolvedDepth, index: index.cast())
                if isGenericParamPack(UInt64(resolvedDepth), UInt64(index)) {
                    target.write("each", context: .context(state: .printKeyword))
                    target.writeSpace()
                    // Remember it for the type that follows: a use site carries
                    // no pack marker, and for a function the signature and the
                    // parameter types share this printer.
                    context.knownPackParameterNames.insert(parameterName)
                }

                let value = isGenericParamValue(UInt64(resolvedDepth), UInt64(index))
                if value != nil {
                    target.write("let", context: .context(state: .printKeyword))
                    target.writeSpace()
                }

                await printDependentGenericParamName(parameterName)

                if let value {
                    target.write(": ")
                    await printName(value)
                }
            }
        }

        target.write(">")
    }

    mutating func printDependentGenericConformanceRequirement(_ name: Node) async {
        await printRequirementSubject(of: name)
        await printOptional(name.children.at(1), prefix: ": ")
    }

    /// Prints a requirement's subject, spelling a pack parameter as
    /// `repeat each A`.
    ///
    /// Source writes a pack constraint `where repeat each A: P`, but the
    /// subject in the mangling is a BARE parameter reference — indistinguishable
    /// from an ordinary parameter, with neither the `repeat` nor the `each`
    /// anywhere in the node. Both are recovered from
    /// ``knownPackParameterNames``, which ``printGenericSignature`` filled in
    /// on this same printer a moment earlier while deciding that the
    /// declaration reads `<each A>`. Without this the constraint printed
    /// `where A1: P`, which does not compile against a pack parameter.
    ///
    /// No parentheses here, unlike a use site: the subject is the bare
    /// parameter with nothing suffixed to it, so `each` has nothing to bind
    /// past.
    mutating func printRequirementSubject(of requirement: Node, suffix: String? = nil) async {
        if let subject = requirement.children.first,
           let parameterName = Self.bareGenericParameterName(of: subject),
           context.knownPackParameterNames.contains(parameterName) {
            target.write("repeat", context: .context(state: .printKeyword))
            target.writeSpace()
            target.write("each", context: .context(state: .printKeyword))
            target.writeSpace()
            await printDependentGenericParamName(parameterName)
            if let suffix { target.write(suffix) }
            return
        }
        await printFirstChild(requirement, suffix: suffix)
    }

    /// The parameter's name when this node is exactly a generic parameter
    /// reference (optionally wrapped in `type`); nil for anything compound,
    /// where `repeat each` would not apply to the node as a whole.
    static func bareGenericParameterName(of node: Node) -> String? {
        var current = node
        if current.kind == .type, let child = current.children.first {
            current = child
        }
        guard current.kind == .dependentGenericParamType else { return nil }
        return current.text
    }

    mutating func printDependentGenericLayoutRequirement(_ name: Node) async {
        guard let layout = name.children.at(1), let layoutCode = layout.text?.unicodeScalars.first else { return }
        await printRequirementSubject(of: name, suffix: ": ")
        switch layoutCode {
        case "U": target.write("_UnknownLayout", context: .context(state: .printType))
        case "R": target.write("_RefCountedObject", context: .context(state: .printType))
        case "N": target.write("_NativeRefCountedObject", context: .context(state: .printType))
        case "C": target.write("AnyObject", context: .context(state: .printType))
        case "D": target.write("_NativeClass", context: .context(state: .printType))
        case "T": target.write("_Trivial", context: .context(state: .printType))
        case "E",
             "e": target.write("_Trivial", context: .context(state: .printType))
        case "M",
             "m": target.write("_TrivialAtMost", context: .context(state: .printType))
        default: break
        }
        if name.children.count > 2 {
            await printOptional(name.children.at(2), prefix: "(")
            await printOptional(name.children.at(3), prefix: ", ")
            target.write(")")
        }
    }

    mutating func printDependentGenericSameTypeRequirement(_ name: Node) async {
        await printRequirementSubject(of: name)
        await printOptional(name.children.at(1), prefix: " == ")
    }

    mutating func printDependentGenericType(_ name: Node) async {
        guard let dependentType = name.children.at(1) else { return }
        if let signature = name.children.first, signature.kind == .dependentGenericSignature {
            await printGenericSignature(signature, enclosingGenericType: name)
        } else {
            await printFirstChild(name)
        }
        await printOptional(dependentType, prefix: dependentType.needSpaceBeforeType ? " " : "")
    }

    mutating func printDependentMemberType(_ name: Node) async {
        context.dependentMemberTypeDepth += 1
        defer { context.dependentMemberTypeDepth -= 1 }
        await printFirstChild(name)
        target.write(".")
        await printOptional(name.children.at(1))
    }

    mutating func printDependentGenericInverseConformanceRequirement(_ name: Node) async {
        await printFirstChild(name, suffix: ": ~")
        switch name.children.at(1)?.index {
        case 0: target.write("Swift.Copyable", context: .context(state: .printType))
        case 1: target.write("Swift.Escapable", context: .context(state: .printType))
        default: target.write("Swift.<bit \(name.children.at(1)?.index ?? 0)>")
        }
    }
}
