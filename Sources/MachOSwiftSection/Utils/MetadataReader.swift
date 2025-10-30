import Foundation
import MachOKit
import Demangling
import MachOFoundation
import SwiftStdlibToolbox
@_spi(Internals) import MachOCaches

private final class MetadataReaderCache: MachOCache<MetadataReaderCache.Entry>, @unchecked Sendable {
    fileprivate static let shared = MetadataReaderCache()

    private override init() {}

    fileprivate struct MangledNameBox: Hashable {
        let wrappedValue: MangledName

        func hash(into hasher: inout Hasher) {
            hasher.combine(wrappedValue.elements)
        }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.wrappedValue.elements == rhs.wrappedValue.elements
        }

        init(_ wrappedValue: MangledName) {
            self.wrappedValue = wrappedValue
        }
    }

    final class Entry {
        @Mutex
        fileprivate var nodeForMangledNameBox: [MangledNameBox: Node] = [:]
    }

    override func buildEntry<MachO>(for machO: MachO) -> Entry? where MachO: MachORepresentableWithCache {
        Entry()
    }

    override func entry<MachO>(in machO: MachO) -> Entry? where MachO: MachORepresentableWithCache {
        super.entry(in: machO)
    }

    func demangleType<MachO: MachOSwiftSectionRepresentableWithCache>(for mangledName: MangledName, in machO: MachO) throws -> Node {
        if let node = entry(in: machO)?.nodeForMangledNameBox[MangledNameBox(mangledName)] {
            return node
        } else {
            let node = try MetadataReader._demangleType(for: mangledName, in: machO)
            entry(in: machO)?.nodeForMangledNameBox[MangledNameBox(mangledName)] = node
            return node
        }
    }
}

public enum MetadataReader<MachO: MachOSwiftSectionRepresentableWithCache> {
//    public static func demangle(for mangledName: MangledName, in machO: MachO) throws -> Node {
//        let rawString = mangledName.rawString
//        if rawString.isSwiftSymbol {
//            return try demangle(for: mangledName, kind: .symbol, in: machO)
//        } else {
//            return try demangleType(for: mangledName, in: machO)
//        }
//    }

    fileprivate static func _demangleType(for mangledName: MangledName, in machO: MachO) throws -> Node {
        return try demangle(for: mangledName, kind: .type, in: machO)
    }

    public static func demangleType(for mangledName: MangledName, in machO: MachO) throws -> Node {
//        return try demangle(for: mangledName, kind: .type, in: machO)
        try MetadataReaderCache.shared.demangleType(for: mangledName, in: machO)
    }

//    public static func demangleSymbol(for mangledName: MangledName, in machO: MachO) throws -> Node {
//        return try demangle(for: mangledName, kind: .symbol, in: machO)
//    }

    public static func demangleType(for symbol: Symbol, in machO: MachO) throws -> Node? {
        return try buildContextManglingForSymbol(symbol, in: machO)
    }

    public static func demangleSymbol(for symbol: Symbol, in machO: MachO) throws -> Node? {
//        return try demangle(for: .init(unsolvedSymbol: unsolvedSymbol), kind: .symbol, in: machOFile)
        return SymbolCache.shared.demangledNode(for: symbol, in: machO)
    }

    public static func demangleContext(for context: ContextDescriptorWrapper, in machO: MachO) throws -> Node {
        return try required(buildContextMangling(context: context, in: machO))
    }

    private static func demangle(for mangledName: MangledName, kind: MangledNameKind, useOpaqueTypeSymbolicReferences: Bool = false, in machO: MachO) throws -> Node {
        let stringValue = switch kind {
        case .type:
            mangledName.typeString
        case .symbol:
            mangledName.symbolString
        }
        let symbolicReferenceResolver: DemangleSymbolicReferenceResolver = { kind, directness, index -> Node? in
            do {
                var result: Node?
                let lookup = mangledName.lookupElements[index]
                let offset = lookup.offset
                guard case .relative(let relativeReference) = lookup.reference else { return nil }
                let relativeOffset = relativeReference.relativeOffset
                switch kind {
                case .context:
                    switch directness {
                    case .direct:
                        if let context = try RelativeDirectPointer<ContextDescriptorWrapper?>(relativeOffset: relativeOffset).resolve(from: offset, in: machO) {
                            if let opaqueTypeDescriptor = context.opaqueTypeDescriptor {
                                let opaqueType = try OpaqueType(descriptor: opaqueTypeDescriptor, in: machO)
//                                result = try .init(kind: .opaqueReturnTypeOf, child: demangleType(for: opaqueType.underlyingTypeArgumentMangledNames[0], in: machO))
                                
                                result = .init(kind: .opaqueTypeDescriptorSymbolicReference, index: address(of: opaqueType.offset, in: machO))
                            } else {
                                result = try buildContextMangling(context: .element(context), in: machO)
                            }
                        }
                    case .indirect:
                        let relativePointer = RelativeIndirectSymbolOrElementPointer<ContextDescriptorWrapper?>(relativeOffset: relativeOffset)
                        if let resolvableElement = try relativePointer.resolve(from: offset, in: machO).asOptional {
                            if case .element(let element) = resolvableElement, let opaqueTypeDescriptor = element.opaqueTypeDescriptor {
                                let opaqueType = try OpaqueType(descriptor: opaqueTypeDescriptor, in: machO)
//                                result = try .init(kind: .opaqueReturnTypeOf, child: demangleType(for: opaqueType.underlyingTypeArgumentMangledNames[0], in: machO))
                                result = .init(kind: .opaqueTypeDescriptorSymbolicReference, index: address(of: opaqueType.offset, in: machO))
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
                    let existentialType = try extendedExistentialTypeShape.existentialType(in: machO).symbolString
                    result = try .init(kind: .uniqueExtendedExistentialTypeShapeSymbolicReference, children: demangleAsNode(existentialType.insertManglePrefix).children)
                case .nonUniqueExtendedExistentialTypeShape:
                    let nonUniqueExtendedExistentialTypeShape = try RelativeDirectPointer<NonUniqueExtendedExistentialTypeShape>(relativeOffset: relativeOffset).resolve(from: offset, in: machO)
                    let existentialType = try nonUniqueExtendedExistentialTypeShape.existentialType(in: machO).symbolString
                    result = try .init(kind: .nonUniqueExtendedExistentialTypeShapeSymbolicReference, children: demangleAsNode(existentialType.insertManglePrefix).children)
                case .objectiveCProtocol:
                    let relativePointer = RelativeDirectPointer<RelativeObjCProtocolPrefix>(relativeOffset: relativeOffset)
                    let objcProtocol = try relativePointer.resolve(from: offset, in: machO)
                    let name = try objcProtocol.mangledName(in: machO).symbolString
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

    private static func buildContextMangling(context: SymbolOrElement<ContextDescriptorWrapper>, in machO: MachO) throws -> Node? {
        switch context {
        case .symbol(let symbol):
            return try buildContextManglingForSymbol(symbol, in: machO)
        case .element(let contextDescriptorProtocol):
            return try buildContextMangling(context: contextDescriptorProtocol, in: machO)
        }
    }

    private static func buildContextMangling(context: ContextDescriptorWrapper, in machO: MachO) throws -> Node? {
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

    private static func buildContextDescriptorMangling(context: SymbolOrElement<ContextDescriptorWrapper>, recursionLimit: Int, in machO: MachO) throws -> Node? {
        guard recursionLimit > 0 else { return nil }
        switch context {
        case .symbol(let symbol):
            return try buildContextManglingForSymbol(symbol, in: machO)
        case .element(let contextDescriptor):
            var demangleSymbol = try buildContextDescriptorMangling(context: contextDescriptor, recursionLimit: recursionLimit, in: machO)

            if demangleSymbol?.kind == .type {
                demangleSymbol = demangleSymbol?.children.first
            }
            return demangleSymbol
        }
    }

    package static func buildGenericSignature(for requirement: GenericRequirementDescriptor, in machO: MachO) throws -> Node? {
        try buildGenericSignature(for: [requirement], in: machO)
    }

    package static func buildGenericSignature(for requirements: GenericRequirementDescriptor..., in machO: MachO) throws -> Node? {
        try buildGenericSignature(for: requirements, in: machO)
    }

    package static func buildGenericSignature(for requirements: [GenericRequirementDescriptor], in machO: MachO) throws -> Node? {
        guard !requirements.isEmpty else { return nil }
        let signatureNode = Node(kind: .dependentGenericSignature)
        var failed = false
        for requirement in requirements {
            if failed {
                break
            }
            let subject = try demangle(for: requirement.paramMangledName(in: machO), kind: .type, in: machO)
            let offset = requirement.offset(of: \.content)
            switch requirement.content {
            case .protocol(let relativeProtocolDescriptorPointer):
                guard let proto = try? readProtocol(offset: offset, pointer: relativeProtocolDescriptorPointer, in: machO) else {
                    failed = true
                    break
                }
                let requirementNode = Node(kind: .dependentGenericConformanceRequirement, children: [subject, proto])
                signatureNode.addChild(requirementNode)
            case .type(let relativeDirectPointer):
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
            case .layout(let genericRequirementLayoutKind):
                if genericRequirementLayoutKind == .class {
                    let requirementNode = Node(kind: .dependentGenericLayoutRequirement, children: [subject, .init(kind: .identifier, contents: .text("C"))])
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
        if failed {
            return nil
        } else {
            return signatureNode
        }
    }

    private static func buildContextDescriptorMangling(context: ContextDescriptorWrapper, recursionLimit: Int, in machO: MachO) throws -> Node? {
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
                nameNode = try .init(kind: .identifier, contents: .text(namedContext.name(in: machO)))
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
            if let requirements = try extensionContext.genericContext(in: machO)?.requirements, let signatureNode = try buildGenericSignature(for: requirements, in: machO) {
                demangling.addChild(signatureNode)
            }
            return demangling
        case .anonymous:
            guard let symbol = try? Symbol.resolve(from: context.contextDescriptor.offset, in: machO), let privateDeclName = try? symbol.demangledNode.first(of: .privateDeclName), let privateDeclNameIdentifier = privateDeclName.children.first else { return parentDemangling }
            let anonNode = Node(kind: .anonymousContext)
            anonNode.addChild(privateDeclNameIdentifier)
            if let parentDemangling {
                anonNode.addChild(parentDemangling)
            }
            return anonNode
        case .module:
            if parentDemangling != nil {
                return nil
            }
            guard let moduleContext = context.moduleContextDescriptor else { return nil }
            return try .init(kind: .module, contents: .text(moduleContext.name(in: machO)))
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
        guard var parentDemangling, var nameNode else { return nil }
        if parentDemangling.kind == .anonymousContext, nameNode.kind == .identifier {
            if parentDemangling.children.count < 2 {
                return nil
            }
            let privateDeclName = Node(kind: .privateDeclName)
            privateDeclName.addChild(parentDemangling.children[0])
            privateDeclName.addChild(nameNode)
            nameNode = privateDeclName
            parentDemangling = parentDemangling.children[1]
        }
        let demangling = Node(kind: kind, children: [parentDemangling, nameNode])

        return demangling
    }

    private static func buildContextManglingForSymbol(_ symbol: Symbol, in machO: MachO) throws -> Node? {
        var demangledSymbol = try demangleAsNode(symbol.name)
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

    private static func adoptAnonymousContextName(context: ContextDescriptorWrapper, parentContextRef: inout SymbolOrElement<ContextDescriptorWrapper>?, outSymbol: inout Node?, in machO: MachO) throws -> Node? {
        outSymbol = nil
        guard let parentContextLocalRef = parentContextRef else { return nil }
        guard case .element(let parentContext) = parentContextRef else { return nil }
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

        guard identifierNode.kind == .identifier, identifierNode.hasText else { return nil }

        guard let namedContext = context.namedContextDescriptor else { return nil }
        guard try namedContext.name(in: machO) == identifierNode.text else { return nil }

        parentContextRef = try parentContext.parent(in: machO)

        outSymbol = mangledNode.children[0]

        return nameChild
    }

    private static func demangleAnonymousContextName(context: SymbolOrElement<ContextDescriptorWrapper>, in machO: MachO) throws -> Node? {
        guard case .element(.anonymous(let context)) = context, let mangledName = try context.mangledName(in: machO) else { return nil }
        return try demangle(for: mangledName, kind: .symbol, in: machO)
    }

    private static func readProtocol(offset: Int, pointer: RelativeProtocolDescriptorPointer, in machO: MachO) throws -> Node? {
        switch pointer {
        case .objcPointer(let objcPointer):
            let objcPrefixElement = try objcPointer.resolve(from: offset, in: machO)
            switch objcPrefixElement {
            case .symbol(let symbol):
                return try buildContextManglingForSymbol(symbol, in: machO)
            case .element(let objcPrefix):
                let mangledName = try objcPrefix.mangledName(in: machO)
                let name = mangledName.symbolString
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
                    return Node(kind: .protocol, children: [.init(kind: .module, contents: .text(objcModule)), .init(kind: .identifier, contents: .text(name))])
                }
            }
        case .swiftPointer(let swiftPointer):
            let resolvableProtocolDescriptor = try swiftPointer.resolve(from: offset, in: machO)
            switch resolvableProtocolDescriptor {
            case .symbol(let symbol):
                return try buildContextManglingForSymbol(symbol, in: machO)
            case .element(let context):
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
