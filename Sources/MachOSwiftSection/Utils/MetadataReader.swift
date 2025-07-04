import Foundation
import MachOKit
import Demangle
import MachOFoundation
import MachOMacro

public struct MetadataReader {
    public static func demangleType<MachO: MachORepresentableWithCache & MachOReadable>(for mangledName: MangledName, in machO: MachO) throws -> Node {
        return try demangle(for: mangledName, kind: .type, in: machO)
    }

    public static func demangleSymbol<MachO: MachORepresentableWithCache & MachOReadable>(for mangledName: MangledName, in machO: MachO) throws -> Node {
        return try demangle(for: mangledName, kind: .symbol, in: machO)
    }

    public static func demangleType<MachO: MachORepresentableWithCache & MachOReadable>(for unsolvedSymbol: Symbol, in machO: MachO) throws -> Node? {
        return try buildContextManglingForSymbol(unsolvedSymbol, in: machO)
    }

    public static func demangleSymbol<MachO: MachORepresentableWithCache & MachOReadable>(for unsolvedSymbol: Symbol, in machO: MachO) throws -> Node? {
//        return try demangle(for: .init(unsolvedSymbol: unsolvedSymbol), kind: .symbol, in: machOFile)
        return SymbolCache.shared.demangledNode(for: unsolvedSymbol, in: machO)
    }

    public static func demangleContext<MachO: MachORepresentableWithCache & MachOReadable>(for context: ContextDescriptorWrapper, in machO: MachO) throws -> Node {
        return try required(buildContextMangling(context: context, in: machO))
    }

    private static func demangle<MachO: MachORepresentableWithCache & MachOReadable>(for mangledName: MangledName, kind: MangledNameKind, useOpaqueTypeSymbolicReferences: Bool = false, in machO: MachO) throws -> Node {
        let stringValue = switch kind {
        case .type:
            mangledName.typeStringValue()
        case .symbol:
            mangledName.symbolStringValue()
        }
//        var demangler = Demangler(scalars: stringValue.unicodeScalars)
        let symbolicReferenceResolver: SymbolicReferenceResolver = { kind, directness, index -> Node? in
            do {
                var result: Node?
                let lookup = mangledName.lookupElements[index]
                let offset = lookup.offset
                guard case let .relative(relativeReference) = lookup.reference else { return nil }
                let relativeOffset = relativeReference.relativeOffset
                switch kind {
                case .context:
                    switch directness {
                    case .direct:
                        if let context = try RelativeDirectPointer<ContextDescriptorWrapper?>(relativeOffset: relativeOffset).resolve(from: offset, in: machO) {
                            if context.opaqueTypeDescriptor != nil {
                                // Try to preserve a reference to an OpaqueTypeDescriptor
                                // symbolically, since we'd like to read out and resolve the type ref
                                // to the underlying type if available.
                                result = .init(kind: .opaqueTypeDescriptorSymbolicReference, contents: .index(context.offset.cast()))
                            } else {
                                result = try buildContextMangling(context: .element(context), in: machO)
                            }
                        }
                    case .indirect:
                        let relativePointer = RelativeIndirectSymbolOrElementPointer<ContextDescriptorWrapper?>(relativeOffset: relativeOffset)
                        if let resolvableElement = try relativePointer.resolve(from: offset, in: machO).asOptional {
                            if case let .element(element) = resolvableElement, element.opaqueTypeDescriptor != nil {
                                // Try to preserve a reference to an OpaqueTypeDescriptor
                                // symbolically, since we'd like to read out and resolve the type ref
                                // to the underlying type if available.
                                result = .init(kind: .opaqueTypeDescriptorSymbolicReference, contents: .index(element.offset.cast()))
                            } else {
                                result = try buildContextMangling(context: resolvableElement, in: machO)
                            }
                        }
                    }
                case .accessorFunctionReference:
                    // The symbolic reference points at a resolver function, but we can't
                    // execute code in the target process to resolve it from here.
                    result = .init(kind: .accessorFunctionReference, contents: .index(address(of: RelativeDirectRawPointer(relativeOffset: relativeOffset).resolveDirectOffset(from: offset), in: machO)))
                case .uniqueExtendedExistentialTypeShape:
                    let extendedExistentialTypeShape = try RelativeDirectPointer<ExtendedExistentialTypeShape>(relativeOffset: relativeOffset).resolve(from: offset, in: machO)
                    let existentialType = try extendedExistentialTypeShape.existentialType(in: machO).symbolStringValue()
                    result = try .init(kind: .uniqueExtendedExistentialTypeShapeSymbolicReference, children: demangleAsNode(existentialType.insertManglePrefix).children)
                case .nonUniqueExtendedExistentialTypeShape:
                    let nonUniqueExtendedExistentialTypeShape = try RelativeDirectPointer<NonUniqueExtendedExistentialTypeShape>(relativeOffset: relativeOffset).resolve(from: offset, in: machO)
                    let existentialType = try nonUniqueExtendedExistentialTypeShape.existentialType(in: machO).symbolStringValue()
                    result = try .init(kind: .nonUniqueExtendedExistentialTypeShapeSymbolicReference, children: demangleAsNode(existentialType.insertManglePrefix).children)
                case .objectiveCProtocol:
                    let relativePointer = RelativeDirectPointer<RelativeObjCProtocolPrefix>(relativeOffset: relativeOffset)
                    let objcProtocol = try relativePointer.resolve(from: offset, in: machO)
                    let name = try objcProtocol.mangledName(in: machO).symbolStringValue()
                    result = try demangleAsNode(name).typeSymbol
                }
                return result
            } catch {
                return nil
            }
        }
        let result: Node
        switch kind {
        case .type:
            result = try demangleAsNode(stringValue, isType: true, symbolicReferenceResolver: symbolicReferenceResolver)
        case .symbol:
            result = try demangleAsNode(stringValue, isType: false, symbolicReferenceResolver: symbolicReferenceResolver)
        }
        return result
    }

    private static func buildContextMangling<MachO: MachORepresentableWithCache & MachOReadable>(context: SymbolOrElement<ContextDescriptorWrapper>, in machO: MachO) throws -> Node? {
        switch context {
        case let .symbol(symbol):
            return try buildContextManglingForSymbol(symbol, in: machO)
        case let .element(contextDescriptorProtocol):
            return try buildContextMangling(context: contextDescriptorProtocol, in: machO)
        }
    }

    private static func buildContextMangling<MachO: MachORepresentableWithCache & MachOReadable>(context: ContextDescriptorWrapper, in machO: MachO) throws -> Node? {
        guard let demangling = try buildContextDescriptorMangling(context: context, recursionLimit: 50, in: machO) else {
            return nil
        }
        let top: Node

        switch context {
        case .type,
             .protocol:
            top = .init(kind: .type, children: [demangling])
        default:
            top = demangling
        }

        return top
    }

    private static func buildContextDescriptorMangling<MachO: MachORepresentableWithCache & MachOReadable>(context: SymbolOrElement<ContextDescriptorWrapper>, recursionLimit: Int, in machO: MachO) throws -> Node? {
        guard recursionLimit > 0 else { return nil }
        switch context {
        case let .symbol(symbol):
            return try buildContextManglingForSymbol(symbol, in: machO)
        case let .element(contextDescriptor):
            var demangleSymbol = try buildContextDescriptorMangling(context: contextDescriptor, recursionLimit: recursionLimit, in: machO)

            if demangleSymbol?.kind == .type {
                demangleSymbol = demangleSymbol?.children.first
            }
            return demangleSymbol
        }
    }

    private static func buildContextDescriptorMangling<MachO: MachORepresentableWithCache & MachOReadable>(context: ContextDescriptorWrapper, recursionLimit: Int, in machO: MachO) throws -> Node? {
        guard recursionLimit > 0 else { return nil }
        var parentDescriptorResult = try context.parent(in: machO)
        var demangledParentNode: Node?
        var nameNode = try adoptAnonymousContextName(context: context, parentContextRef: &parentDescriptorResult, outSymbol: &demangledParentNode, in: machO)
//        guard let parentDescriptorResult else { return nil }
        var parentDemangling: Node?

        if let parentDescriptor = parentDescriptorResult {
            parentDemangling = try buildContextDescriptorMangling(context: parentDescriptor, recursionLimit: recursionLimit - 1, in: machO)
            if parentDemangling == nil, demangledParentNode == nil {
                return nil
            }
        }

        if let demangledParentNode, parentDemangling == nil || parentDemangling!.kind == .anonymousContext {
            parentDemangling = demangledParentNode
        }

        let kind: Node.Kind

        func getContextName() throws -> Bool {
            if nameNode != nil {
                return true
            } else if let namedContext = context.namedContextDescriptor {
                nameNode = try .init(kind: .identifier, contents: .name(namedContext.name(in: machO)))
                return true
            } else {
                return false
            }
        }

        switch context.contextDescriptor.layout.flags.kind {
        case .class:
            guard try getContextName() else { return nil }
            kind = .class
        case .struct:
            guard try getContextName() else { return nil }
            kind = .structure
        case .enum:
            guard try getContextName() else { return nil }
            kind = .enum
        case .protocol:
            guard try getContextName() else { return nil }
            kind = .protocol
        case .extension:
            guard let parentDemangling else { return nil }
            guard let extensionContext = context.extensionContextDescriptor else { return nil }
            guard let extendedContext = try extensionContext.extendedContext(in: machO) else { return nil }
            guard let demangledExtendedContext = try demangle(for: extendedContext, kind: .type, in: machO).extensionSymbol else { return nil }
            let demangling = Node(kind: .extension, children: [parentDemangling, demangledExtendedContext])
            if let requirements = try extensionContext.genericContext(in: machO)?.requirements {
                let signatureNode = Node(kind: .dependentGenericSignature)
                var failed = false
                for requirement in requirements {
                    if failed {
                        break
                    }
                    let subject = try demangle(for: requirement.paramManagedName(in: machO), kind: .type, in: machO)
                    let offset = requirement.offset(of: \.content)
                    switch requirement.content {
                    case let .protocol(relativeProtocolDescriptorPointer):
                        guard let proto = try? readProtocol(offset: offset, pointer: relativeProtocolDescriptorPointer, in: machO) else {
                            failed = true
                            break
                        }
                        let requirementNode = Node(kind: .dependentGenericConformanceRequirement, children: [subject, proto])
                        signatureNode.addChild(requirementNode)
                    case let .type(relativeDirectPointer):
                        let mangledName = try relativeDirectPointer.resolve(from: offset, in: machO)
                        guard let type = try? demangle(for: mangledName, kind: .type, in: machO) else {
                            failed = true
                            break
                        }
                        let nodeKind: Node.Kind

                        if requirement.flags.kind == .sameType {
                            nodeKind = .dependentGenericSameTypeRequirement
                        } else {
                            nodeKind = .dependentGenericConformanceRequirement
                        }

                        let requirementNode = Node(kind: nodeKind, children: [subject, type])
                        signatureNode.addChild(requirementNode)
                    case let .layout(genericRequirementLayoutKind):
                        if genericRequirementLayoutKind == .class {
                            let requirementNode = Node(kind: .dependentGenericLayoutRequirement, children: [subject, .init(kind: .identifier, contents: .name("C"))])
                            signatureNode.addChild(requirementNode)
                        } else {
                            failed = true
                        }
                    case .conformance:
                        break
                    case .invertedProtocols:
                        break
                    }
                }
                if !failed {
                    demangling.addChild(signatureNode)
                }
            }
            return demangling
        case .anonymous:
//            var anonNode = SwiftSymbol(kind: .anonymousContext)
//            anonNode.children.append(.init(kind: .identifier, contents: .name(context.offset.description)))
//            if let parentDemangling {
//                anonNode.children.append(parentDemangling)
//            }
//            return anonNode
            return parentDemangling
        case .module:
            if parentDemangling != nil {
                return nil
            }
            guard let moduleContext = context.moduleContextDescriptor else { return nil }
            return try .init(kind: .module, contents: .name(moduleContext.name(in: machO)))
        case .opaqueType:
            guard let parentDescriptorResult else { return nil }
            if parentDemangling?.kind == .anonymousContext {
                guard var mangledNode = try demangleAnonymousContextName(context: parentDescriptorResult, in: machO) else {
                    return nil
                }
                if mangledNode.kind == .global {
                    mangledNode = mangledNode.children[0]
                }
                let opaqueNode = Node(kind: .opaqueReturnTypeOf, children: [mangledNode])
                return opaqueNode
            } else if let parentDemangling, parentDemangling.kind == .module {
                let opaqueNode = Node(kind: .opaqueReturnTypeOf, children: [parentDemangling])
                return opaqueNode
            } else {
                return nil
            }
        default:
            return nil
        }
        guard let parentDemangling, let nameNode else { return nil }
        if parentDemangling.kind == .anonymousContext, nameNode.kind == .identifier {
            if parentDemangling.children.count < 2 {
                return nil
            }
        }
        let demangling = Node(kind: kind, children: [parentDemangling, nameNode])

        return demangling
    }

    private static func buildContextManglingForSymbol<MachO: MachORepresentableWithCache & MachOReadable>(_ symbol: Symbol, in machO: MachO) throws -> Node? {
        var demangledSymbol = try demangleAsNode(symbol.stringValue)
        if demangledSymbol.kind == .global {
            demangledSymbol = demangledSymbol.children[0]
        }
        switch demangledSymbol.kind {
        case .nominalTypeDescriptor,
             .protocolDescriptor:
            demangledSymbol = demangledSymbol.children[0]
        case .opaqueTypeDescriptor:
            demangledSymbol = demangledSymbol.children[0]
        default:
            return nil
        }
        return demangledSymbol
    }

    private static func adoptAnonymousContextName<MachO: MachORepresentableWithCache & MachOReadable>(context: ContextDescriptorWrapper, parentContextRef: inout SymbolOrElement<ContextDescriptorWrapper>?, outSymbol: inout Node?, in machO: MachO) throws -> Node? {
        outSymbol = nil
        guard let parentContextLocalRef = parentContextRef else { return nil }
        guard case let .element(parentContext) = parentContextRef else { return nil }
        guard context.isType || context.isProtocol else { return nil }
//        guard case let .anonymous(anonymousParent) = parentContext else { return nil }
        guard var mangledNode = try demangleAnonymousContextName(context: parentContextLocalRef, in: machO) else { return nil }
        if mangledNode.kind == .global {
            mangledNode = mangledNode.children[0]
        }
        guard mangledNode.children.count >= 2 else { return nil }

        let nameChild = mangledNode.children[1]

        guard nameChild.kind == .privateDeclName || nameChild.kind == .localDeclName, nameChild.children.count >= 2 else { return nil }

        let identifierNode = nameChild.children[1]

        guard identifierNode.kind == .identifier, identifierNode.contents.hasName else { return nil }

        guard let namedContext = context.namedContextDescriptor else { return nil }
        guard try namedContext.name(in: machO) == identifierNode.contents.name else { return nil }

        parentContextRef = try parentContext.parent(in: machO)

        outSymbol = mangledNode.children[0]

        return nameChild
    }

    private static func demangleAnonymousContextName<MachO: MachORepresentableWithCache & MachOReadable>(context: SymbolOrElement<ContextDescriptorWrapper>, in machO: MachO) throws -> Node? {
        guard case let .element(.anonymous(context)) = context, let mangledName = try context.mangledName(in: machO) else { return nil }
        return try demangle(for: mangledName, kind: .symbol, in: machO)
    }

    private static func readProtocol<MachO: MachORepresentableWithCache & MachOReadable>(offset: Int, pointer: RelativeProtocolDescriptorPointer, in machO: MachO) throws -> Node? {
        switch pointer {
        case let .objcPointer(objcPointer):
            let objcPrefixElement = try objcPointer.resolve(from: offset, in: machO)
            switch objcPrefixElement {
            case let .symbol(symbol):
                return try buildContextManglingForSymbol(symbol, in: machO)
            case let .element(objcPrefix):
                let mangledName = try objcPrefix.mangledName(in: machO)
                let name = mangledName.symbolStringValue()
                if name.starts(with: "_TtP") {
                    var demangled = try demangle(for: mangledName, kind: .symbol, in: machO)
                    while demangled.kind == .global ||
                        demangled.kind == .typeMangling ||
                        demangled.kind == .type ||
                        demangled.kind == .protocolList ||
                        demangled.kind == .typeList ||
                        demangled.kind == .type {
                        if demangled.children.count != 1 {
                            return nil
                        }
                        demangled = demangled.children.first!
                    }
                    return demangled
                } else {
                    return Node(kind: .protocol, children: [.init(kind: .module, contents: .name(objcModule)), .init(kind: .identifier, contents: .name(name))])
                }
            }
        case let .swiftPointer(swiftPointer):
            let resolvableProtocolDescriptor = try swiftPointer.resolve(from: offset, in: machO)
            switch resolvableProtocolDescriptor {
            case let .symbol(symbol):
                return try buildContextManglingForSymbol(symbol, in: machO)
            case let .element(context):
                return try buildContextMangling(context: .protocol(context), in: machO)
            }
        }
    }
}

extension Node {
    fileprivate var typeSymbol: Node? {
        func enumerate(_ child: Node) -> Node? {
            if child.kind == .type {
                return child
            }

            if child.kind == .enum || child.kind == .structure || child.kind == .class || child.kind == .protocol {
                return .init(kind: .type, contents: .none, children: [child])
            }

            for child in child.children {
                if let result = enumerate(child) {
                    return result
                }
            }
            return nil
        }
        return enumerate(self)
    }

    fileprivate var typeNonWrapperSymbol: Node? {
        func enumerate(_ child: Node) -> Node? {
            if child.kind == .enum || child.kind == .structure || child.kind == .class || child.kind == .protocol {
                return child
            }

            for child in child.children {
                if let result = enumerate(child) {
                    return result
                }
            }
            return nil
        }
        return enumerate(self)
    }

    fileprivate var extensionSymbol: Node? {
        typeNonWrapperSymbol
    }

    func nodes(for kind: Node.Kind) -> [Node] {
        var nodes: [Node] = []
        func enumerate(_ child: Node) {
            if child.kind == kind {
                nodes.append(child)
            }
            for child in child.children {
                enumerate(child)
            }
        }
        enumerate(self)
        return nodes
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        if index < 0 || index >= count {
            return nil
        }
        return self[index]
    }
}
