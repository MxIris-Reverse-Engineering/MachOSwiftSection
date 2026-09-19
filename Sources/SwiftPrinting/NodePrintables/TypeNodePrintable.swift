import SwiftDeclaration
import SwiftDeclarationRendering
import Demangling

/// The slice of printer state the type layer reads.
protocol TypeNodePrintableContext: NodePrintableContext {
    /// The declaration whose opaque return types `printOpaqueReturnType`
    /// asks the delegate to resolve; nil while a bare type is being printed.
    var targetNode: Node? { get }
}

protocol TypeNodePrintable: NodePrintable where Context: TypeNodePrintableContext {
    mutating func printNameInType(_ name: Node) async -> Bool
    mutating func printType(_ name: Node) async
}

extension TypeNodePrintable {
    mutating func printNameInType(_ name: Node) async -> Bool {
        switch name.kind {
        case .type,
             .weak,
             .unowned,
             .unmanaged:
            await printFirstChild(name)
        case .builtinTypeName:
            target.write(name.text ?? "", context: .context(for: name, state: .printType))
        case .builtinTupleType:
            target.write("Builtin.TheTupleType", context: .context(for: name, state: .printType))
        case .enum,
             .structure,
             .class,
             .protocol,
             .typeAlias:
            // The full qualified-name print (module, dots, identifier) for
            // this nominal reference runs inside one scope so the target can
            // group the writes into a single span keyed by `name`.
            target.pushTypeReferenceScope(name)
            await printType(name)
            target.popTypeReferenceScope()
        case .tuple:
            await printTuple(name)
        case .protocolList:
            await printProtocolList(name)
        case .protocolListWithClass:
            await printProtocolListWithClass(name)
        case .protocolListWithAnyObject:
            await printProtocolListWithAnyObject(name)
        case .typeList:
            await printTypeList(name)
        case .pack:
            await printPack(name)
        case .constrainedExistential:
            await printConstrainedExistential(name)
        case .constrainedExistentialRequirementList:
            await printChildren(name, separator: ", ")
        case .constrainedExistentialSelf:
            target.write("Self", context: .context(for: name, state: .printKeyword))
        case .metatype:
            await printMetatype(name)
        case .existentialMetatype:
            await printExistentialMetatype(name)
        case .opaqueReturnType:
            await printOpaqueReturnType(name)
        case .opaqueReturnTypeOf:
            // The by-name spelling of an unexpanded opaque reference (the
            // standalone-file case). Its child is the declaring entity, which
            // a type printer does not handle — so delegate whole, exactly as
            // `printOpaqueType` does, instead of printing children into an
            // empty `<<opaque return type of >>`.
            target.write(await name.print(using: .default), context: .context(for: name, state: .printType))
        case .opaqueType:
            await printOpaqueType(name)
        case .symbolicExtendedExistentialType:
            await printSymbolicExtendedExistentialType(name)
        default:
            return false
        }
        return true
    }

    mutating func printOpaqueReturnType(_ node: Node) async {
        target.write("some", context: .context(for: node, state: .printKeyword))
        if let targetNode = context.targetNode, let opaqueType = await delegate?.opaqueType(forNode: targetNode, index: node.first(of: .opaqueReturnTypeIndex)?.index?.int) {
            target.writeSpace()
            target.write(opaqueType)
        }
    }

    /// An opaque type reference `OpaqueTypeRewriter` could NOT expand.
    ///
    /// Reaching this printer at all means expansion already failed — an
    /// expanded reference is replaced in the tree and never arrives here — so
    /// the honest rendering is the reference itself, spelled exactly as the
    /// dump path spells it.
    ///
    /// Delegated to the upstream `NodePrinter` rather than reimplemented,
    /// because child 0 is an entity node (`.function` / `.variable` /
    /// `.extension` / `.static` / `.getter` …) and this is a TYPE printer that
    /// handles none of those. Open-coding it would print
    /// `<<opaque return type of >>` — an empty middle, worse than the status
    /// quo. Delegation also makes the two paths byte-identical by
    /// construction, which is the same contract `accessor function at N`
    /// carries.
    ///
    /// It previously printed child 2 — the node's generic ARGUMENT LIST —
    /// which rendered a single-argument reference as the conforming type
    /// itself (`typealias B = ProbeClient.Outer`): a real, fully-qualified,
    /// wrong type. That came from commit `798bca8c` "Fix Interface missing
    /// type list of opaque type", whose observation was right (the arguments
    /// were being dropped) and whose fix was not. Since proposal 0033 every
    /// locatable reference is expanded by the rewriter and carries its
    /// arguments along, so child 2 has no reason to be printed here.
    mutating func printOpaqueType(_ name: Node) async {
        // A signature's reference is by name — a symbol carries no symbolic
        // references — so it can be spelled the way a textual interface
        // names an opaque archetype without an image in hand (evolution
        // proposal `opaque-reference-spelling-and-member-projection`).
        // A reference whose owner cannot be named keeps the upstream text.
        let spelled = name.spellingUnexpandedOpaqueReferences(as: .textualInterface)
        if spelled !== name, let text = spelled.text {
            target.write(text, context: .context(for: name, state: .printType))
            return
        }
        target.write(await name.print(using: .default), context: .context(for: name, state: .printType))
    }

    mutating func printType(_ name: Node) async {
        if name.kind == .type, let firstChild = name.children.first {
            await printType(firstChild)
            return
        }
        guard let contextNode = name.children.first else { return }

        var resolvedCImportedModule = false
        if shouldPrintContext() {
            let writtenUnitCountBeforeContext = target.writtenUnitCount
            if contextNode.kind == .module {
                let siblingIdentifier = name.children.at(1)?.text
                resolvedCImportedModule = await printModule(contextNode, siblingIdentifier: siblingIdentifier)
                // The module→type dot stays inside this leaf's scope so a
                // fully-qualified top-level name (`AppKit.MenuItem`) selects
                // as one span.
                if target.writtenUnitCount != writtenUnitCountBeforeContext {
                    target.write(".")
                }
            } else {
                await printName(contextNode, options: NodePrintOptions(asPrefixContext: true))
                // A nested type's separator dot joins two independently
                // navigable spans (the parent type vs this leaf), so it
                // belongs to neither — emit it under a barrier, otherwise it
                // fuses onto this leaf's span (`.Locator`) and gets selected
                // with it.
                if target.writtenUnitCount != writtenUnitCountBeforeContext {
                    target.pushTypeReferenceScope(nil)
                    target.write(".")
                    target.popTypeReferenceScope()
                }
            }
        }

        if let declarationName = name.children.at(1) {
            if declarationName.kind != .privateDeclName {
                if declarationName.kind == .identifier {
                    // A resolved C-imported module may pair with an identifier
                    // whose C spelling differs from its Swift one — `__C`'s
                    // `CFStringRef` imports as `CFString` (ClangImporter strips
                    // the CF `Ref` suffix). Rewrite only when the module itself
                    // resolved, so an unresolved `__C.CFStringRef` never
                    // renders as the half-translated `__C.CFString` — and pass
                    // the reference's declaration category, because a C name
                    // can denote a class and a protocol at once (`NSObject`).
                    if resolvedCImportedModule,
                       let identifierText = declarationName.text,
                       let delegate,
                       let swiftSpelling = await delegate.swiftName(forCName: identifierText, category: CImportedTypeNameCategory(nodeKind: name.kind)) {
                        target.write(swiftSpelling, context: .context(for: declarationName, parentKind: name.kind, state: .printIdentifier))
                    } else {
                        await printIdentifier(declarationName, parentKind: name.kind)
                    }
                } else {
                    await printName(declarationName)
                }
            }
            if let privateDeclName = name.children.first(where: { $0.kind == .privateDeclName }) {
                await printPrivateDeclName(privateDeclName, parentKind: name.kind)
            }
        }
    }

    mutating func printTypeList(_ name: Node) async {
        await printChildren(name)
    }

    /// A variadic-generic parameter pack's arguments, as they appear in a bound
    /// generic type (`Predicate<each Input>` instantiated as
    /// `Predicate<Foundation.URL>`).
    ///
    /// Rendered as the bare comma-separated elements — deliberately NOT the
    /// upstream `Pack{…}` spelling. Upstream's `NodePrinter` serves debug
    /// demangling, where naming the pack is the point; this printer's product
    /// is a `.swiftinterface`, where `Predicate<Pack{URL}>` does not compile
    /// and `Predicate<URL>` is what the source said. Printing the elements
    /// bare also lets them fold straight into the enclosing argument list,
    /// which is exactly the ABI meaning of a pack expansion in that position.
    ///
    /// Previously unhandled, so every pack argument printed as the empty
    /// string: 718 occurrences in SwiftUI, surfacing as `Predicate<>` and
    /// `ConformingTuple<>`.
    mutating func printPack(_ name: Node) async {
        await printChildren(name, separator: ", ")
    }

    /// A parameterized existential — `any P<Element>` (SE-0353 / SE-0346).
    ///
    /// The mangling carries the desugared form: the protocol, plus same-type
    /// requirements pinning its associated types. Upstream prints that shape
    /// literally (`any P<Self.Element == Int>`), which is right for debug
    /// demangling and is not compilable Swift.
    ///
    /// The sugar is recoverable for the same reason it is on an opaque type
    /// (see `Documentations/Internal/OpaqueReturnTypeResolution.md` §2.4): a
    /// parameterized existential CANNOT be written with a `where` clause in
    /// source, so a same-type requirement sitting here can only have come from
    /// primary-associated-type sugar. Reading the requirement's right-hand
    /// side back as the argument therefore needs no protocol facts.
    ///
    /// What DOES need them is ORDER: with several primaries, the requirement
    /// list is canonically sorted, not declaration-ordered, so `P<A, B>` and
    /// `P<B, A>` are indistinguishable from here. That case degrades to a bare
    /// `any P` rather than guessing — an argument list in the wrong order is a
    /// real, wrong, compiling type. No sample in the surveyed binaries has
    /// more than one requirement; wiring the multi-primary order through
    /// `ProtocolFactsResolver` is left to the follow-up noted in the proposal.
    mutating func printConstrainedExistential(_ name: Node) async {
        await printFirstChild(name, prefix: "any ", prefixContext: .context(for: name, state: .printKeyword))
        guard let requirementList = name.children.at(1),
              requirementList.children.count == 1,
              let argument = primaryAssociatedTypeArgument(ofRequirement: requirementList.children[0])
        else { return }
        await printOptional(argument, prefix: "<", suffix: ">")
    }

    /// The right-hand side of a `Self.Associated == Argument` requirement, or
    /// nil when the requirement is not that shape (a conformance or layout
    /// constraint, or a same-type whose subject is not rooted at `Self`).
    private func primaryAssociatedTypeArgument(ofRequirement requirement: Node) -> Node? {
        guard requirement.kind == .dependentGenericSameTypeRequirement,
              let subject = requirement.children.at(0),
              let argument = requirement.children.at(1)
        else { return nil }
        guard subject.contains(Node.Kind.constrainedExistentialSelf) else { return nil }
        return argument
    }

    mutating func printProtocolList(_ name: Node) async {
        guard let typeList = name.children.first else { return }
        if typeList.children.isEmpty {
            target.write("Any", context: .context(for: name, state: .printKeyword))
        } else {
            await printChildren(typeList, separator: " & ")
        }
    }

    mutating func printProtocolListWithClass(_ name: Node) async {
        guard name.children.count >= 2 else { return }
        await printOptional(name.children.at(1), suffix: " & ")
        if let protocolsTypeList = name.children.first?.children.first {
            await printChildren(protocolsTypeList, separator: " & ")
        }
    }

    mutating func printProtocolListWithAnyObject(_ name: Node) async {
        guard let protocolListNode = name.children.first, let protocolsTypeList = protocolListNode.children.first else { return }
        if protocolsTypeList.children.count > 0 {
            await printChildren(protocolsTypeList, suffix: " & ", separator: " & ")
        }
        target.write("Swift", context: .context(for: name, state: .printModule))
        target.write(".")
        target.write("AnyObject", context: .context(for: name, parentKind: .protocol, state: .printIdentifier))
    }

    mutating func printTuple(_ name: Node) async {
        await printChildren(name, prefix: "(", suffix: ")", separator: ", ")
    }

    mutating func printMetatype(_ name: Node) async {
        if name.children.count == 2 {
            await printFirstChild(name, suffix: " ")
        }
        guard let type = name.children.at(name.children.count == 2 ? 1 : 0)?.children.first else { return }
        let needParens = !type.isSimpleType
        target.write(needParens ? "(" : "")
        await printName(type)
        target.write(needParens ? ")" : "")
        target.write(".")
        target.write(type.kind.isExistentialType ? "Protocol" : "Type", context: .context(for: name, state: .printKeyword))
    }

    mutating func printExistentialMetatype(_ name: Node) async {
        if name.children.count == 2 {
            await printFirstChild(name, suffix: " ")
        }
        await printOptional(name.children.at(name.children.count == 2 ? 1 : 0), suffix: ".Type")
    }

    mutating func printSymbolicExtendedExistentialType(_ name: Node) async {
        guard let second = name.children.at(1) else { return }
        await printName(second)
        if let third = name.children.at(2) {
            target.write(", ")
            await printName(third)
        }
    }
}
