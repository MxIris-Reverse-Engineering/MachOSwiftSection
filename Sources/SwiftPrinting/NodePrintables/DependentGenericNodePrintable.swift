import SwiftDeclaration
import Demangling

protocol DependentGenericNodePrintable: NodePrintable {
    var isProtocol: Bool { get }
    mutating func printNameInDependentGeneric(_ name: Node, context: Context?) async -> Bool
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
    mutating func printNameInDependentGeneric(_ name: Node, context: Context?) async -> Bool {
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
        // This is the pack the enclosing `repeat` expands over (the
        // expansion's count type), which source spells `each A`.
        // Parenthesized unconditionally — see `printPackExpansion` for why a
        // bare `each` is rejected after a suffix.
        if let packParameterName = expandedPackParameterName, name.text == packParameterName {
            target.write("(")
            target.write("each", context: .context(for: name, state: .printKeyword))
            target.writeSpace()
            await printDependentGenericParamName(packParameterName)
            target.write(")")
            return
        }
        await printDependentGenericParamName(name.text ?? "")
    }

    mutating func printDependentGenericParamName(_ name: String) async {
        if isProtocol, name == "A" {
            target.write("Self", context: .context(state: .printKeyword))
        } else {
            target.write(name)
        }
    }

    mutating func printGenericSignature(_ name: Node, enclosingGenericType: Node? = nil) async {
        var numGenericParams = 0
        for c in name.children {
            guard c.kind == .dependentGenericParamCount else { break }
            numGenericParams += 1
        }

        // A signature that introduces no parameters of its own has nothing to
        // bracket. An extension member whose parameters all belong to the
        // extended type arrives here with every count at zero, and bracketing
        // it unconditionally (as upstream's `NodePrinter` does — correct for a
        // debug demangle) yields `init<>(windowID: String) where ...`, which
        // does not compile. 122 occurrences in SwiftUI; the dump path never
        // reaches this code, so it showed none of them.
        let declaredParameterCount = (0 ..< numGenericParams).reduce(into: 0) { total, depth in
            total += Int(name.children.at(depth)?.index ?? 0)
        }
        guard declaredParameterCount > 0 else { return }

        target.write("<")
        var firstRequirement = numGenericParams
        for var c in name.children.dropFirst(numGenericParams) {
            if c.kind == .type {
                c = c.children.first ?? c
            }
            guard c.kind == .dependentGenericParamPackMarker || c.kind == .dependentGenericParamValueMarker else {
                break
            }
            firstRequirement += 1
        }

        let isGenericParamPack = { (depth: UInt64, index: UInt64) -> Bool in
            for var child in name.children.dropFirst(numGenericParams).prefix(firstRequirement) {
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
            for var child in name.children.dropFirst(numGenericParams).prefix(firstRequirement) {
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

        for gpDepth in 0 ..< numGenericParams {
            if gpDepth != 0 {
                target.write("><")
            }

            guard let count = name.children.at(gpDepth)?.index else { continue }
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
                let resolvedDepth = depths?[index.cast()] ?? gpDepth.cast()

                if isGenericParamPack(UInt64(resolvedDepth), UInt64(index)) {
                    target.write("each", context: .context(state: .printKeyword))
                    target.writeSpace()
                }

                let value = isGenericParamValue(UInt64(resolvedDepth), UInt64(index))
                if value != nil {
                    target.write("let", context: .context(state: .printKeyword))
                    target.writeSpace()
                }

                await printDependentGenericParamName(genericParameterName(depth: resolvedDepth, index: index.cast()))

                if let value {
                    target.write(": ")
                    _ = await printName(value)
                }
            }
        }

//        if firstRequirement != name.children.count {
//            if options.contains(.displayWhereClauses) {
//                target.write(" where ")
//                printSequence(name.children.dropFirst(firstRequirement), separator: ", ")
//            }
//        }
        target.write(">")
    }

    mutating func printDependentGenericConformanceRequirement(_ name: Node) async {
        await printFirstChild(name)
        _ = await printOptional(name.children.at(1), prefix: ": ")
    }

    mutating func printDependentGenericLayoutRequirement(_ name: Node) async {
        guard let layout = name.children.at(1), let c = layout.text?.unicodeScalars.first else { return }
        await printFirstChild(name, suffix: ": ")
        switch c {
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
            _ = await printOptional(name.children.at(2), prefix: "(")
            _ = await printOptional(name.children.at(3), prefix: ", ")
            target.write(")")
        }
    }

    mutating func printDependentGenericSameTypeRequirement(_ name: Node) async {
        await printFirstChild(name)
        _ = await printOptional(name.children.at(1), prefix: " == ")
    }

    mutating func printDependentGenericType(_ name: Node) async {
        guard let depType = name.children.at(1) else { return }
        if let sig = name.children.first, sig.kind == .dependentGenericSignature {
            await printGenericSignature(sig, enclosingGenericType: name)
        } else {
            await printFirstChild(name)
        }
        _ = await printOptional(depType, prefix: depType.needSpaceBeforeType ? " " : "")
    }

    mutating func printDependentMemberType(_ name: Node) async {
        dependentMemberTypeDepth += 1
        defer { dependentMemberTypeDepth -= 1 }
        await printFirstChild(name)
        target.write(".")
        _ = await printOptional(name.children.at(1))
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
